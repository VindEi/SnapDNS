using System.Diagnostics;
using System.Net.NetworkInformation;
using SnapDns.Service.Models;
using SnapDns.Service.Utilities;

namespace SnapDns.Service.Services;

public partial class SystemDnsService(ILogger<SystemDnsService> logger, DnsProxyService dnsProxy)
{
    private static readonly SemaphoreSlim _asyncLock = new(1, 1);

    // FIX: Expanded junk/virtual interface filter to exclude Npcap, WinPcap, and standard packet-capture drivers
    private static readonly string[] Junk = [
        "virtual", "pseudo", "filter", "miniport", "vmware", "hyper-v",
        "qos", "debugger", "microsoft", "bridge", "bluetooth", "loopback", "wireguard", "wfp",
        "npcap", "pcap", "packet", "tap", "tun", "vpn"
    ];

    public async Task<PipeResponse> ApplyDnsConfiguration(string adapterName, DnsConfiguration config)
    {
        await _asyncLock.WaitAsync();
        try
        {
            if (!string.IsNullOrWhiteSpace(config.DohUrl) || !string.IsNullOrWhiteSpace(config.DotHostname))
            {
                bool started = await dnsProxy.StartAsync(config.DohUrl, config.DotHostname);
                if (!started)
                {
                    return new PipeResponse 
                    { 
                        Success = false, 
                        Message = "Failed to start local DNS proxy (Port 53 may be in use by another application)." 
                    };
                }
                config.PrimaryDns = "127.0.0.1";
                config.SecondaryDns = "";
                config.Ipv6Primary = "";
                config.Ipv6Secondary = "";
            }
            else { dnsProxy.Stop(); }

            bool success = false;
            if (OperatingSystem.IsWindows())
            {
                success = SetWindowsDns(adapterName, config);
            }
            else if (OperatingSystem.IsMacOS())
            {
                string serviceName = GetMacOsServiceName(adapterName) ?? adapterName;

                List<string> args = ["-setdnsservers", serviceName];
                if (!string.IsNullOrEmpty(config.PrimaryDns)) args.Add(config.PrimaryDns);
                if (!string.IsNullOrEmpty(config.SecondaryDns)) args.Add(config.SecondaryDns);
                if (!string.IsNullOrEmpty(config.Ipv6Primary)) args.Add(config.Ipv6Primary);
                if (!string.IsNullOrEmpty(config.Ipv6Secondary)) args.Add(config.Ipv6Secondary);

                if (args.Count == 2) args.Add("Empty"); 
                success = ProcessHelper.Run("networksetup", args, logger);
            }
            else if (OperatingSystem.IsLinux())
            {
                List<string> args = ["dns", adapterName];
                if (!string.IsNullOrEmpty(config.PrimaryDns)) args.Add(config.PrimaryDns);
                if (!string.IsNullOrEmpty(config.SecondaryDns)) args.Add(config.SecondaryDns);
                if (!string.IsNullOrEmpty(config.Ipv6Primary)) args.Add(config.Ipv6Primary);
                if (!string.IsNullOrEmpty(config.Ipv6Secondary)) args.Add(config.Ipv6Secondary);

                success = ProcessHelper.Run("resolvectl", args, logger);

                if (success)
                {
                    ProcessHelper.Run("resolvectl", ["domain", adapterName, "~."], logger);
                }
            }

            return new PipeResponse { Success = success };
        }
        finally { _asyncLock.Release(); }
    }

    private bool SetWindowsDns(string adapter, DnsConfiguration config)
    {
        // 1. Configure IPv4
        List<string> pArgs = ["interface", "ipv4", "set", "dns", $"name={adapter}", "static", config.PrimaryDns, "primary"];
        bool pSuccess = ProcessHelper.Run("netsh", pArgs, logger);

        if (!string.IsNullOrEmpty(config.SecondaryDns))
        {
            List<string> sArgs = ["interface", "ipv4", "add", "dns", $"name={adapter}", config.SecondaryDns, "index=2"];
            ProcessHelper.Run("netsh", sArgs, logger);
        }

        // 2. Configure IPv6 if supported by the hardware interface
        var ni = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n => n.Name == adapter);
        bool supportsIpv6 = ni != null && ni.Supports(NetworkInterfaceComponent.IPv6);

        if (supportsIpv6)
        {
            if (!string.IsNullOrEmpty(config.Ipv6Primary))
            {
                List<string> ip6pArgs = ["interface", "ipv6", "set", "dns", $"name={adapter}", "static", config.Ipv6Primary, "primary"];
                ProcessHelper.Run("netsh", ip6pArgs, logger);

                if (!string.IsNullOrEmpty(config.Ipv6Secondary))
                {
                    List<string> ip6sArgs = ["interface", "ipv6", "add", "dns", $"name={adapter}", config.Ipv6Secondary, "index=2"];
                    ProcessHelper.Run("netsh", ip6sArgs, logger);
                }
            }
            else
            {
                ProcessHelper.Run("netsh", ["interface", "ipv6", "set", "dnsservers", $"name={adapter}", "source=dhcp"], logger);
            }
        }

        return pSuccess;
    }

    public async Task<PipeResponse> ResetToDhcp(string adapter)
    {
        await _asyncLock.WaitAsync();
        try
        {
            dnsProxy.Stop();
            bool success = false;
            if (OperatingSystem.IsWindows())
            {
                success = ProcessHelper.Run("netsh", ["interface", "ipv4", "set", "dnsservers", $"name={adapter}", "source=dhcp"], logger);
                
                var ni = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n => n.Name == adapter);
                if (ni != null && ni.Supports(NetworkInterfaceComponent.IPv6))
                {
                    ProcessHelper.Run("netsh", ["interface", "ipv6", "set", "dnsservers", $"name={adapter}", "source=dhcp"], logger);
                }
            }
            else if (OperatingSystem.IsMacOS())
            {
                string serviceName = GetMacOsServiceName(adapter) ?? adapter;
                success = ProcessHelper.Run("networksetup", ["-setdnsservers", serviceName, "Empty"], logger);
            }
            else if (OperatingSystem.IsLinux())
            {
                success = ProcessHelper.Run("resolvectl", ["revert", adapter], logger);
            }
            return new PipeResponse { Success = success };
        }
        finally { _asyncLock.Release(); }
    }

    private static string? GetMacOsServiceName(string bsdName)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "networksetup",
                Arguments = "-listnetworkserviceorder",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true
            };
            using var p = Process.Start(psi);
            if (p == null) return null;
            
            string output = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            
            var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
            foreach (var line in lines)
            {
                if (line.Contains($"Device: {bsdName}"))
                {
                    int openParen = line.IndexOf('(');
                    if (openParen > 0)
                    {
                        string servicePart = line[..openParen].Trim();
                        int closeParenIndex = servicePart.IndexOf(')');
                        if (closeParenIndex >= 0)
                        {
                            servicePart = servicePart[(closeParenIndex + 1)..].Trim();
                        }
                        else
                        {
                            int firstSpace = servicePart.IndexOf(' ');
                            if (firstSpace > 0) servicePart = servicePart[(firstSpace + 1)..].Trim();
                        }
                        return servicePart;
                    }
                }
            }
        }
        catch { }
        return null;
    }

    public static Task<PipeResponse> FlushDns()
    {
        if (OperatingSystem.IsWindows()) ProcessHelper.Run("ipconfig", ["/flushdns"]);
        else if (OperatingSystem.IsMacOS()) ProcessHelper.Run("killall", ["-HUP", "mDNSResponder"]);
        else if (OperatingSystem.IsLinux()) ProcessHelper.Run("resolvectl", ["flush-caches"]);
        return Task.FromResult(new PipeResponse { Success = true });
    }

    public Task<PipeResponse> GetSyncState(string? manualAdapterName)
    {
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

    private DnsConfiguration GetCurrentDns(NetworkInterface ni)
    {
        try
        {
            var dns = ni.GetIPProperties().DnsAddresses
                .Select(d => d.ToString()).ToList();

            var firstDns = dns.FirstOrDefault() ?? "DHCP";
            return new DnsConfiguration 
            { 
                PrimaryDns = firstDns, 
                SecondaryDns = dns.Skip(1).FirstOrDefault() ?? "",
                DohUrl = firstDns == "127.0.0.1" ? (dnsProxy.ActiveDohUrl ?? "") : "",
                DotHostname = firstDns == "127.0.0.1" ? (dnsProxy.ActiveDotHostname ?? "") : ""
            };
        }
        catch (Exception ex)
        {
            logger.LogWarning("Failed to retrieve IP properties for adapter {Adapter}: {Msg}", ni.Name, ex.Message);
            return new DnsConfiguration { PrimaryDns = "AUTO", SecondaryDns = "" };
        }
    }
}