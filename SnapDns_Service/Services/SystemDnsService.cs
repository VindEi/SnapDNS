using System.Net.NetworkInformation;
using SnapDns.Service.Models;
using SnapDns.Service.Utilities;

namespace SnapDns.Service.Services;

public partial class SystemDnsService(ILogger<SystemDnsService> logger, DnsProxyService dnsProxy)
{
    private static readonly SemaphoreSlim _asyncLock = new(1, 1);

    // FIX: restored the adapter filter
    private static readonly string[] Junk = [
        "virtual", "pseudo", "filter", "miniport", "vmware", "hyper-v",
        "qos", "debugger", "microsoft", "bridge", "bluetooth", "loopback", "wireguard", "wfp"
    ];

    public async Task<PipeResponse> ApplyDnsConfiguration(string adapterName, DnsConfiguration config)
    {
        await _asyncLock.WaitAsync();
        try
        {
            if (!string.IsNullOrWhiteSpace(config.DohUrl) || !string.IsNullOrWhiteSpace(config.DotHostname))
            {
                await dnsProxy.StartAsync(config.DohUrl, config.DotHostname);
                config.PrimaryDns = "127.0.0.1";
                config.SecondaryDns = "";
            }
            else { dnsProxy.Stop(); }

            bool success = false;
            if (OperatingSystem.IsWindows()) success = SetWindowsDns(adapterName, config.PrimaryDns, config.SecondaryDns);
            else if (OperatingSystem.IsMacOS()) success = ProcessHelper.Run("networksetup", ["-setdnsservers", adapterName, config.PrimaryDns], logger);
            else if (OperatingSystem.IsLinux()) success = ProcessHelper.Run("resolvectl", ["dns", adapterName, config.PrimaryDns], logger);

            return new PipeResponse { Success = success };
        }
        finally { _asyncLock.Release(); }
    }

    private bool SetWindowsDns(string adapter, string primary, string secondary)
    {
        List<string> pArgs = ["interface", "ipv4", "set", "dns", $"name={adapter}", "static", primary, "primary"];
        bool pSuccess = ProcessHelper.Run("netsh", pArgs, logger);

        if (!string.IsNullOrEmpty(secondary))
        {
            List<string> sArgs = ["interface", "ipv4", "add", "dns", $"name={adapter}", secondary, "index=2"];
            ProcessHelper.Run("netsh", sArgs, logger);
        }
        return pSuccess;
    }

    public async Task<PipeResponse> ResetToDhcp(string adapter)
    {
        dnsProxy.Stop();
        bool success = false;
        if (OperatingSystem.IsWindows()) success = ProcessHelper.Run("netsh", ["interface", "ipv4", "set", "dnsservers", $"name={adapter}", "source=dhcp"], logger);
        else if (OperatingSystem.IsMacOS()) success = ProcessHelper.Run("networksetup", ["-setdnsservers", adapter, "Empty"], logger);
        else if (OperatingSystem.IsLinux()) success = ProcessHelper.Run("resolvectl", ["revert", adapter], logger);
        return new PipeResponse { Success = success };
    }

    public static Task<PipeResponse> FlushDns()
    {
        if (OperatingSystem.IsWindows()) ProcessHelper.Run("ipconfig", ["/flushdns"]);
        else if (OperatingSystem.IsMacOS()) ProcessHelper.Run("killall", ["-HUP", "mDNSResponder"]);
        else if (OperatingSystem.IsLinux()) ProcessHelper.Run("resolvectl", ["flush-caches"]);
        return Task.FromResult(new PipeResponse { Success = true });
    }

    public static Task<PipeResponse> GetSyncState(string? manualAdapterName)
    {
        // FIX: Re-applied filtering logic to exclude junk/virtual adapters
        var all = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                        !Junk.Any(j => n.Description.Contains(j, StringComparison.OrdinalIgnoreCase)) &&
                        !Junk.Any(j => n.Name.Contains(j, StringComparison.OrdinalIgnoreCase)))
            .ToList();

        var preferred = all.FirstOrDefault(n => n.GetIPProperties().GatewayAddresses.Count > 0);
        var target = all.FirstOrDefault(n => n.Name == manualAdapterName) ?? preferred;

        return Task.FromResult(new PipeResponse
        {
            Success = true,
            Adapters = [.. all.Select(n => n.Name)],
            PreferredAdapterName = preferred?.Name,
            Configuration = target != null ? GetCurrentDns(target) : null
        });
    }

    private static DnsConfiguration GetCurrentDns(NetworkInterface ni)
    {
        var dns = ni.GetIPProperties().DnsAddresses
            .Where(d => d.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
            .Select(d => d.ToString()).ToList();

        return new DnsConfiguration { PrimaryDns = dns.FirstOrDefault() ?? "DHCP", SecondaryDns = dns.Skip(1).FirstOrDefault() ?? "" };
    }
}