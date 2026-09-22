using System.Diagnostics;
using System.Net.NetworkInformation;
using SnapDns.Service.Models;
using SnapDns.Service.Utilities;

namespace SnapDns.Service.Services;

public partial class SystemDnsService(ILogger<SystemDnsService> logger, DnsProxyService dnsProxy)
{
    private static readonly SemaphoreSlim _asyncLock = new(1, 1);

    private static readonly string[] Junk = [
        "virtual", "pseudo", "filter", "miniport", "vmware", "hyper-v",
        "qos", "debugger", "microsoft", "bridge", "bluetooth", "loopback", "wireguard", "wfp",
        "npcap", "pcap", "packet", "tap", "tun", "vpn"
    ];

    public async Task<PipeResponse> ApplyDnsConfiguration(string adapterName, DnsConfiguration config, bool disableIpv6 = false)
    {
        await _asyncLock.WaitAsync();
        try
        {
            SetIpv6InterfaceState(adapterName, enabled: !disableIpv6);

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
            else
            {
                dnsProxy.Stop();
            }

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
        finally
        {
            _asyncLock.Release();
        }
    }

    private bool SetWindowsDns(string adapter, DnsConfiguration config)
    {
        List<string> pArgs = ["interface", "ipv4", "set", "dns", $"name={adapter}", "static", config.PrimaryDns, "primary", "validate=no"];
        bool pSuccess = ProcessHelper.Run("netsh", pArgs, logger);

        if (!string.IsNullOrEmpty(config.SecondaryDns))
        {
            List<string> sArgs = ["interface", "ipv4", "add", "dns", $"name={adapter}", config.SecondaryDns, "index=2", "validate=no"];
            ProcessHelper.Run("netsh", sArgs, logger);
        }

        var ni = NetworkInterface.GetAllNetworkInterfaces().FirstOrDefault(n => n.Name == adapter);
        bool supportsIpv6 = ni != null && ni.Supports(NetworkInterfaceComponent.IPv6);

        if (supportsIpv6)
        {
            if (!string.IsNullOrEmpty(config.Ipv6Primary))
            {
                List<string> ip6pArgs = ["interface", "ipv6", "set", "dns", $"name={adapter}", "static", config.Ipv6Primary, "primary", "validate=no"];
                ProcessHelper.Run("netsh", ip6pArgs, logger);

                if (!string.IsNullOrEmpty(config.Ipv6Secondary))
                {
                    List<string> ip6sArgs = ["interface", "ipv6", "add", "dns", $"name={adapter}", config.Ipv6Secondary, "index=2", "validate=no"];
                    ProcessHelper.Run("netsh", ip6sArgs, logger);
                }
            }
            else
            {
                if (config.PrimaryDns == "127.0.0.1")
                {
                    ProcessHelper.Run("netsh", ["interface", "ipv6", "delete", "dnsservers", $"name={adapter}", "all"], logger);
                }
                else
                {
                    ProcessHelper.Run("netsh", ["interface", "ipv6", "set", "dnsservers", $"name={adapter}", "source=dhcp"], logger);
                }
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
            SetIpv6InterfaceState(adapter, enabled: true);

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
        finally
        {
            _asyncLock.Release();
        }
    }

    private void SetIpv6InterfaceState(string adapter, bool enabled)
    {
        if (string.IsNullOrWhiteSpace(adapter)) return;

        try
        {
            if (OperatingSystem.IsWindows())
            {
                var ni = NetworkInterface.GetAllNetworkInterfaces()
                    .FirstOrDefault(n => n.Name.Equals(adapter, StringComparison.OrdinalIgnoreCase));
                if (ni != null && ni.Supports(NetworkInterfaceComponent.IPv6) == enabled)
                {
                    return;
                }

                string cmd = enabled ? "Enable-NetAdapterBinding" : "Disable-NetAdapterBinding";
                ProcessHelper.Run("powershell", ["-NoProfile", "-NonInteractive", "-Command", $"{cmd} -Name '{adapter}' -ComponentID ms_tcpip6"], logger);
            }
            else if (OperatingSystem.IsLinux())
            {
                string procPath = $"/proc/sys/net/ipv6/conf/{adapter}/disable_ipv6";
                if (File.Exists(procPath))
                {
                    string currentVal = File.ReadAllText(procPath).Trim();
                    string desiredVal = enabled ? "0" : "1";
                    if (currentVal == desiredVal)
                    {
                        return;
                    }
                }

                string val = enabled ? "0" : "1";
                ProcessHelper.Run("sysctl", ["-w", $"net.ipv6.conf.{adapter}.disable_ipv6={val}"], logger);
            }
            else if (OperatingSystem.IsMacOS())
            {
                string serviceName = GetMacOsServiceName(adapter) ?? adapter;
                string flag = enabled ? "-setv6automatic" : "-setv6off";
                ProcessHelper.Run("networksetup", [flag, serviceName], logger);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning("Failed to set IPv6 state ({State}) on adapter {Adapter}: {Msg}", enabled, adapter, ex.Message);
        }
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
            for (int i = 0; i < lines.Length; i++)
            {
                if (lines[i].Contains($"Device: {bsdName}") && i > 0)
                {
                    string prevLine = lines[i - 1].Trim();
                    int closeParen = prevLine.IndexOf(')');
                    if (closeParen >= 0 && closeParen < prevLine.Length - 1)
                    {
                        return prevLine[(closeParen + 1)..].Trim();
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

        var preferred = all.FirstOrDefault(n => HasActiveGateway(n));
        var target = all.FirstOrDefault(n => n.Name == manualAdapterName) ?? preferred;

        return Task.FromResult(new PipeResponse
        {
            Success = true,
            Adapters = [.. all.Select(n => n.Name)],
            PreferredAdapterName = preferred?.Name,
            Configuration = target != null ? GetCurrentDns(target) : null
        });
    }

    private static bool HasActiveGateway(NetworkInterface ni)
    {
        try
        {
            return ni.GetIPProperties().GatewayAddresses.Count > 0;
        }
        catch
        {
            return false;
        }
    }

    private DnsConfiguration GetCurrentDns(NetworkInterface ni)
    {
        try
        {
            var ipProps = ni.GetIPProperties();
            var allDns = ipProps.DnsAddresses;

            var ipv4Dns = allDns.Where(d => d.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                                .Select(d => d.ToString()).ToList();

            string primaryV4 = ipv4Dns.FirstOrDefault() ?? "";
            string secondaryV4 = ipv4Dns.Skip(1).FirstOrDefault() ?? "";

            bool isLocalProxy = primaryV4 == "127.0.0.1";
            bool isDhcp = false;

            if (!isLocalProxy)
            {
                if (OperatingSystem.IsWindows())
                {
                    isDhcp = IsWindowsDnsDhcp(ni.Id);
                }
                else if (OperatingSystem.IsMacOS())
                {
                    isDhcp = IsMacDnsDhcp(ni.Name);
                }
                else if (OperatingSystem.IsLinux())
                {
                    isDhcp = IsLinuxDnsDhcp(ni.Name);
                }
            }

            string primaryV6 = "";
            string secondaryV6 = "";

            if (!isLocalProxy)
            {
                ResolveIpv6DnsStatus(ni, ipProps, out primaryV6, out secondaryV6);
            }

            return new DnsConfiguration
            {
                Name = isDhcp ? "DHCP" : "",
                PrimaryDns = primaryV4,
                SecondaryDns = secondaryV4,
                Ipv6Primary = primaryV6,
                Ipv6Secondary = secondaryV6,
                DohUrl = isLocalProxy ? (dnsProxy.ActiveDohUrl ?? "") : "",
                DotHostname = isLocalProxy ? (dnsProxy.ActiveDotHostname ?? "") : ""
            };
        }
        catch (Exception ex)
        {
            logger.LogWarning("Failed to retrieve IP properties for adapter {Adapter}: {Msg}", ni.Name, ex.Message);
            return new DnsConfiguration { PrimaryDns = "AUTO", SecondaryDns = "" };
        }
    }

    private static void ResolveIpv6DnsStatus(NetworkInterface ni, IPInterfaceProperties ipProps, out string v6Primary, out string v6Secondary)
    {
        v6Primary = "";
        v6Secondary = "";

        bool hasStaticV6 = false;
        string[] staticServers = [];

        if (OperatingSystem.IsWindows())
        {
            hasStaticV6 = TryGetStaticIpv6Windows(ni.Id, out staticServers);
        }
        else if (OperatingSystem.IsMacOS())
        {
            hasStaticV6 = TryGetStaticIpv6Mac(ni.Name, out staticServers);
        }
        else if (OperatingSystem.IsLinux())
        {
            hasStaticV6 = TryGetStaticIpv6Linux(ni.Name, out staticServers);
        }

        if (hasStaticV6 && staticServers.Length > 0)
        {
            v6Primary = staticServers[0];
            if (staticServers.Length > 1) v6Secondary = staticServers[1];
            return;
        }

        if (HasGlobalIpv6Address(ipProps))
        {
            var realIpv6Dns = ipProps.DnsAddresses
                .Where(d => d.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 &&
                            !d.IsIPv6SiteLocal &&
                            !d.IsIPv6LinkLocal)
                .Select(d => d.ToString())
                .ToList();

            v6Primary = realIpv6Dns.Count > 0 ? "DHCP" : "";
        }
    }

    private static bool HasGlobalIpv6Address(IPInterfaceProperties ipProps)
    {
        try
        {
            return ipProps.UnicastAddresses.Any(a =>
                a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 &&
                !a.Address.IsIPv6LinkLocal &&
                !a.Address.IsIPv6SiteLocal &&
                !a.Address.Equals(System.Net.IPAddress.IPv6Loopback));
        }
        catch
        {
            return false;
        }
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static bool TryGetStaticIpv6Windows(string guid, out string[] servers)
    {
        servers = [];
        try
        {
            string subKey = $@"SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\{guid}";
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(subKey);
            if (key != null)
            {
                var val = key.GetValue("NameServer") as string;
                if (!string.IsNullOrWhiteSpace(val))
                {
                    servers = val.Split([',', ' '], StringSplitOptions.RemoveEmptyEntries);
                    return servers.Length > 0;
                }
            }
        }
        catch { }
        return false;
    }

    private static bool TryGetStaticIpv6Mac(string adapterName, out string[] servers)
    {
        servers = [];
        try
        {
            string serviceName = GetMacOsServiceName(adapterName) ?? adapterName;
            var psi = new ProcessStartInfo
            {
                FileName = "networksetup",
                Arguments = $"-getdnsservers \"{serviceName}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true
            };
            using var p = Process.Start(psi);
            if (p != null)
            {
                string output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                if (!output.Contains("aren't any DNS Servers", StringComparison.OrdinalIgnoreCase))
                {
                    var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    servers = lines.Where(l => System.Net.IPAddress.TryParse(l, out var ip) &&
                                               ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 &&
                                               !ip.IsIPv6SiteLocal &&
                                               !ip.IsIPv6LinkLocal).ToArray();
                    return servers.Length > 0;
                }
            }
        }
        catch { }
        return false;
    }

    private static bool TryGetStaticIpv6Linux(string adapterName, out string[] servers)
    {
        servers = [];
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "resolvectl",
                Arguments = $"dns \"{adapterName}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true
            };
            using var p = Process.Start(psi);
            if (p != null)
            {
                string output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                int colonIdx = output.IndexOf(':');
                if (colonIdx >= 0)
                {
                    string raw = output[(colonIdx + 1)..].Trim();
                    if (!string.IsNullOrWhiteSpace(raw))
                    {
                        var tokens = raw.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                        servers = tokens.Where(t => System.Net.IPAddress.TryParse(t, out var ip) &&
                                                    ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6 &&
                                                    !ip.IsIPv6SiteLocal &&
                                                    !ip.IsIPv6LinkLocal).ToArray();
                        return servers.Length > 0;
                    }
                }
            }
        }
        catch { }
        return false;
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static bool IsWindowsDnsDhcp(string guid)
    {
        try
        {
            string subKey = $@"SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{guid}";
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(subKey);
            if (key != null)
            {
                var val = key.GetValue("NameServer") as string;
                return string.IsNullOrWhiteSpace(val);
            }
        }
        catch { }
        return false;
    }

    private static bool IsMacDnsDhcp(string adapterName)
    {
        try
        {
            string serviceName = GetMacOsServiceName(adapterName) ?? adapterName;
            var psi = new ProcessStartInfo
            {
                FileName = "networksetup",
                Arguments = $"-getdnsservers \"{serviceName}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true
            };
            using var p = Process.Start(psi);
            if (p != null)
            {
                string output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                return output.Contains("aren't any DNS Servers", StringComparison.OrdinalIgnoreCase);
            }
        }
        catch { }
        return false;
    }

    private static bool IsLinuxDnsDhcp(string adapterName)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "resolvectl",
                Arguments = $"dns \"{adapterName}\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true
            };
            using var p = Process.Start(psi);
            if (p != null)
            {
                string output = p.StandardOutput.ReadToEnd();
                p.WaitForExit();
                int colonIdx = output.IndexOf(':');
                if (colonIdx >= 0)
                {
                    string servers = output[(colonIdx + 1)..].Trim();
                    return string.IsNullOrWhiteSpace(servers);
                }
            }
        }
        catch { }
        return false;
    }
}