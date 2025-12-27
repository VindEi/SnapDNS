using SnapDns.Core.Interfaces;
using SnapDns.Core.Ipc;
using SnapDns.Core.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading.Tasks;

namespace SnapDns.Core.Services;

/// <summary>
/// Implements the logic for applying DNS configurations via IPC, checking latency, and managing network adapters.
/// </summary>
public class DnsService : IDnsService
{
    private readonly PipeClient _pipeClient;

    public DnsService()
    {
        _pipeClient = new PipeClient();
    }

    // --- Core DNS Application Functions (Delegated to Service via Named Pipe) ---

    public async Task<bool> ApplyDnsConfigurationAsync(string adapterName, DnsConfiguration configuration)
    {
        var request = new PipeRequest
        {
            Command = PipeCommandType.ApplyDns,
            AdapterName = adapterName,
            Configuration = configuration
        };

        var response = await _pipeClient.SendCommandAsync(request);
        return response.Success;
    }

    public async Task<bool> ResetToDhcpAsync(string adapterName)
    {
        var request = new PipeRequest
        {
            Command = PipeCommandType.ResetDhcp,
            AdapterName = adapterName,
            Configuration = null
        };

        var response = await _pipeClient.SendCommandAsync(request);
        return response.Success;
    }

    public async Task<DnsConfiguration?> GetCurrentDnsConfigurationAsync(string adapterName)
    {
        var request = new PipeRequest
        {
            Command = PipeCommandType.GetConfiguration,
            AdapterName = adapterName
        };

        var response = await _pipeClient.SendCommandAsync(request);

        if (response.Success && response.Configuration != null)
        {
            return response.Configuration;
        }
        return null;
    }

    // --- Latency/Utility Functions ---

    public async Task<long> CheckLatencyAsync(DnsConfiguration configuration)
    {
        if (string.IsNullOrWhiteSpace(configuration.PrimaryDns))
        {
            return -1;
        }

        try
        {
            using var ping = new Ping();
            // 2-second timeout
            var reply = await ping.SendPingAsync(configuration.PrimaryDns, 2000);

            if (reply.Status == IPStatus.Success)
            {
                return reply.RoundtripTime;
            }

            return -1;
        }
        catch
        {
            return -1;
        }
    }

    // Starts the SnapDnsService Windows service with elevated privileges

    public async Task<bool> TryStartServiceAsync()
    {
        // Only works on Windows for now
        if (!System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(System.Runtime.InteropServices.OSPlatform.Windows))
            return false;

        try
        {
            var processInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "net",
                Arguments = "start SnapDnsService",
                UseShellExecute = true, // Required to trigger UAC
                Verb = "runas",         // Request Admin privileges
                CreateNoWindow = true,
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden
            };

            var process = System.Diagnostics.Process.Start(processInfo);
            if (process == null) return false;

            await process.WaitForExitAsync();

            // Return true if exit code is 0 (Success) or 2 (Already running)
            return process.ExitCode == 0 || process.ExitCode == 2;
        }
        catch
        {
            // User declined UAC or error
            return false;
        }
    }


    // --- Adapter Management Functions ---

    public Task<List<string>> GetNetworkAdaptersAsync()
    {
        var adapters = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n =>
                n.OperationalStatus == OperationalStatus.Up &&
                n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                n.NetworkInterfaceType != NetworkInterfaceType.Tunnel &&
                n.NetworkInterfaceType != NetworkInterfaceType.Ppp &&
                n.NetworkInterfaceType != NetworkInterfaceType.Unknown
            )
            .Select(n => string.IsNullOrWhiteSpace(n.Description) ? n.Name : $"{n.Name} ({n.Description})")
            .ToList();

        return Task.FromResult(adapters);
    }

    public Task<string?> GetPreferredAdapterNameAsync()
    {
        var interfaces = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n =>
                n.OperationalStatus == OperationalStatus.Up &&
                n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                n.GetIPProperties().GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork)
            )
            .ToList();

        // 1. Prioritize Ethernet
        var preferred = interfaces.FirstOrDefault(n => n.NetworkInterfaceType == NetworkInterfaceType.Ethernet);
        if (preferred != null) return Task.FromResult<string?>(preferred.Description);

        // 2. Prioritize Wi-Fi
        preferred = interfaces.FirstOrDefault(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211);
        if (preferred != null) return Task.FromResult<string?>(preferred.Description);

        // 3. Fallback
        preferred = interfaces.FirstOrDefault();
        return Task.FromResult<string?>(preferred?.Description);
    }

    public async Task<bool> FlushDnsAsync()
    {
        var request = new PipeRequest
        {
            Command = PipeCommandType.FlushDns
        };

        var response = await _pipeClient.SendCommandAsync(request);
        return response.Success;
    }
}