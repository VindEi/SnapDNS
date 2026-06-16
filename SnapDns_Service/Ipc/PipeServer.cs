using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using SnapDns.Service.Models;
using SnapDns.Service.Services;

namespace SnapDns.Service.Ipc;

public partial class PipeServer(ILogger<PipeServer> logger, SystemDnsService dnsService) : BackgroundService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    // FIX: Dynamically resolves Windows Pipe names vs. rooted Unix Domain Socket paths to prevent sandboxing locks
    private static string GetPipeName()
    {
        return OperatingSystem.IsWindows() ? "SnapDns_IPC_v1" : "/var/run/snapdns.sock";
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (logger.IsEnabled(LogLevel.Information))
            logger.LogInformation("SnapDns IPC Server active on: {PipeName}", GetPipeName());

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
        string pipeName = GetPipeName();

        if (!OperatingSystem.IsWindows())
        {
            // Passing a fully rooted path (/var/run/...) tells .NET Core to bypass /tmp/ and create the socket at this exact path
            var pipe = new NamedPipeServerStream(pipeName, PipeDirection.InOut, -1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);

            // Open up read/write permissions on the Unix Domain Socket so non-root GUI apps can send commands
            if (OperatingSystem.IsLinux() || OperatingSystem.IsMacOS())
            {
                try
                {
                    if (File.Exists(pipeName))
                    {
                        File.SetUnixFileMode(pipeName, 
                            UnixFileMode.UserRead | UnixFileMode.UserWrite |
                            UnixFileMode.GroupRead | UnixFileMode.GroupWrite |
                            UnixFileMode.OtherRead | UnixFileMode.OtherWrite);
                    }
                }
                catch (Exception ex)
                {
                    // Gracefully ignore if the current file system doesn't fully support permission alterations
                }
            }
            return pipe;
        }

        var ps = new PipeSecurity();
        
        var interactiveSid = new SecurityIdentifier(WellKnownSidType.InteractiveSid, null);
        ps.AddAccessRule(new PipeAccessRule(interactiveSid, PipeAccessRights.ReadWrite, AccessControlType.Allow));

        var currentUserSid = WindowsIdentity.GetCurrent().User;
        if (currentUserSid != null)
        {
            ps.AddAccessRule(new PipeAccessRule(currentUserSid, PipeAccessRights.FullControl, AccessControlType.Allow));
        }

        return NamedPipeServerStreamAcl.Create(
            pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, ps);
    }

    private async Task HandleConnectionAsync(NamedPipeServerStream server, CancellationToken ct)
    {
        string requestJson = await IOHelper.ReadStringAsync(server, ct);
        if (string.IsNullOrWhiteSpace(requestJson)) return;

        // FIX: Utilize the compile-time Source Generation Context for deserialization
        var request = JsonSerializer.Deserialize(requestJson, SourceGenerationContext.Default.PipeRequest);
        if (request == null) return;

        if (!string.IsNullOrEmpty(request.AdapterName) && request.AdapterName.Any(c => ";|&<>\"".Contains(c))) return;

        if (logger.IsEnabled(LogLevel.Information))
            logger.LogInformation("IPC Command: {Command} -> {Adapter}", request.Command, request.AdapterName);

        PipeResponse response = await (request.Command switch
        {
            PipeCommandType.getSyncState => dnsService.GetSyncState(request.AdapterName),
            PipeCommandType.applyDns => dnsService.ApplyDnsConfiguration(request.AdapterName, request.Configuration!),
            PipeCommandType.resetDhcp => dnsService.ResetToDhcp(request.AdapterName),
            PipeCommandType.flushDns => SystemDnsService.FlushDns(),
            _ => Task.FromResult(new PipeResponse { Success = false, Message = "Forbidden" })
        });

        // FIX: Utilize the compile-time Source Generation Context for serialization
        await IOHelper.WriteStringAsync(server, JsonSerializer.Serialize(response, SourceGenerationContext.Default.PipeResponse), ct);

        if (OperatingSystem.IsWindows() && server.IsConnected)
        {
            try { server.WaitForPipeDrain(); } catch { }
        }
    }
}