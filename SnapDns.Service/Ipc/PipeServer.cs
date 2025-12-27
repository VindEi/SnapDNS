using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SnapDns.Core.Ipc;
using SnapDns.Core.Models;
using SnapDns.Service.Services;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;

namespace SnapDns.Service.Ipc
{
    public class PipeServer(ILogger<PipeServer> logger, SystemDnsService dnsService) : BackgroundService
    {
        private const int MaxServerInstances = 10;
        private static readonly JsonSerializerOptions ReadJsonOptions = new() { PropertyNameCaseInsensitive = true };
        private static readonly JsonSerializerOptions WriteJsonOptions = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        };

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            logger.LogInformation("SnapDns Named Pipe Server is starting on '{PipeName}'.", PipeConstants.PipeName);

            while (!stoppingToken.IsCancellationRequested)
            {
                NamedPipeServerStream? server = null;
                try
                {
                    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                    {
                        var pipeSecurity = GetPipeSecurity();
                        server = NamedPipeServerStreamAcl.Create(
                            PipeConstants.PipeName,
                            PipeDirection.InOut,
                            MaxServerInstances,
                            PipeTransmissionMode.Byte,
                            PipeOptions.Asynchronous,
                            0,
                            0,
                            pipeSecurity
                        );
                    }
                    else
                    {
                        server = new NamedPipeServerStream(
                            PipeConstants.PipeName,
                            PipeDirection.InOut,
                            MaxServerInstances,
                            PipeTransmissionMode.Byte,
                            PipeOptions.Asynchronous
                        );
                    }

                    await server.WaitForConnectionAsync(stoppingToken);
                    _ = HandleClientConnectionAsync(server, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    server?.Dispose();
                    break;
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error in Pipe listening loop.");
                    server?.Dispose();
                    await Task.Delay(1000, stoppingToken);
                }
            }
        }

        [SupportedOSPlatform("windows")]
        private static PipeSecurity GetPipeSecurity()
        {
            var pipeSecurity = new PipeSecurity();
            pipeSecurity.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            pipeSecurity.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            pipeSecurity.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null), PipeAccessRights.ReadWrite, AccessControlType.Allow));
            return pipeSecurity;
        }

        private async Task HandleClientConnectionAsync(NamedPipeServerStream server, CancellationToken stoppingToken)
        {
            PipeResponse response;
            try
            {
                string jsonRequest = await IOHelper.ReadStringAsync(server, stoppingToken);

                if (string.IsNullOrWhiteSpace(jsonRequest)) return;

                PipeRequest? request = JsonSerializer.Deserialize<PipeRequest>(jsonRequest, ReadJsonOptions);

                if (request == null)
                {
                    response = new PipeResponse { Success = false, Message = "Invalid request format." };
                }
                else
                {
                    response = request.Command switch
                    {
                        PipeCommandType.ApplyDns => request.Configuration == null
                            ? new PipeResponse { Success = false, Message = "Missing configuration." }
                            : dnsService.ApplyDnsConfiguration(request.AdapterName, request.Configuration),

                        PipeCommandType.ResetDhcp => dnsService.ResetToDhcp(request.AdapterName),
                        PipeCommandType.GetConfiguration => dnsService.GetCurrentDnsConfiguration(request.AdapterName),
                        PipeCommandType.GetAdapters => dnsService.GetNetworkAdapters(),
                        PipeCommandType.GetPreferredAdapter => dnsService.GetPreferredAdapterName(),
                        PipeCommandType.FlushDns => dnsService.FlushDns(),

                        _ => new PipeResponse { Success = false, Message = $"Unknown command: {request.Command}" },
                    };
                }

                string jsonResponse = JsonSerializer.Serialize(response, WriteJsonOptions);
                await IOHelper.WriteStringAsync(server, jsonResponse, stoppingToken);

                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    server.WaitForPipeDrain();
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing client.");
            }
            finally
            {
                if (server.IsConnected) server.Disconnect();
                server.Dispose();
            }
        }
    }
}