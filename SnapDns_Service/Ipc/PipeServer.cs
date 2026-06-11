using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using SnapDns.Service.Models;
using SnapDns.Service.Services;

namespace SnapDns.Service.Ipc;

public partial class PipeServer(ILogger<PipeServer> logger, SystemDnsService dnsService) : BackgroundService
{
    private const string PipeName = "SnapDns_IPC_v1";
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (logger.IsEnabled(LogLevel.Information))
            logger.LogInformation("SnapDns IPC Server active on: {PipeName}", PipeName);

        while (!stoppingToken.IsCancellationRequested)
        {
            NamedPipeServerStream? server = null;
            try
            {
                server = CreatePipeStream();
                await server.WaitForConnectionAsync(stoppingToken);

                _ = Task.Run(async () =>
                {
                    try { await HandleConnectionAsync(server, stoppingToken); }
                    catch (Exception ex) { if (logger.IsEnabled(LogLevel.Debug)) logger.LogDebug("Client session ended: {Message}", ex.Message); }
                    finally
                    {
                        if (server.IsConnected) server.Disconnect();
                        server.Dispose();
                    }
                }, stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                server?.Dispose();
                if (logger.IsEnabled(LogLevel.Warning)) logger.LogWarning("Pipe Error: {Message}", ex.Message);
                await Task.Delay(1000, stoppingToken);
            }
        }
    }

    private static NamedPipeServerStream CreatePipeStream()
    {
        if (!OperatingSystem.IsWindows())
            return new NamedPipeServerStream(PipeName, PipeDirection.InOut, -1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);

        var ps = new PipeSecurity();
        var everyoneSid = new SecurityIdentifier(WellKnownSidType.WorldSid, null);
        ps.AddAccessRule(new PipeAccessRule(everyoneSid, PipeAccessRights.ReadWrite, AccessControlType.Allow));

        return NamedPipeServerStreamAcl.Create(
            PipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, ps);
    }

    private async Task HandleConnectionAsync(NamedPipeServerStream server, CancellationToken ct)
    {
        string requestJson = await IOHelper.ReadStringAsync(server, ct);
        if (string.IsNullOrWhiteSpace(requestJson)) return;

        var request = JsonSerializer.Deserialize<PipeRequest>(requestJson, JsonOptions);
        if (request == null) return;

        // Security: Block injection
        if (!string.IsNullOrEmpty(request.AdapterName) && request.AdapterName.Any(c => ";|&<>\"".Contains(c))) return;

        if (logger.IsEnabled(LogLevel.Information))
            logger.LogInformation("IPC Command: {Command} -> {Adapter}", request.Command, request.AdapterName);

        PipeResponse response = await (request.Command switch
        {
            PipeCommandType.getSyncState => SystemDnsService.GetSyncState(request.AdapterName),
            PipeCommandType.applyDns => dnsService.ApplyDnsConfiguration(request.AdapterName, request.Configuration!),
            PipeCommandType.resetDhcp => dnsService.ResetToDhcp(request.AdapterName),
            PipeCommandType.flushDns => SystemDnsService.FlushDns(),
            _ => Task.FromResult(new PipeResponse { Success = false, Message = "Forbidden" })
        });

        await IOHelper.WriteStringAsync(server, JsonSerializer.Serialize(response, JsonOptions), ct);

        if (OperatingSystem.IsWindows() && server.IsConnected)
        {
            try { server.WaitForPipeDrain(); } catch { }
        }
    }
}