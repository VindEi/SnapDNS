using Microsoft.Extensions.Logging;
using SnapDns.Core.Ipc;
using SnapDns.Core.Models;
using System.Diagnostics;
using System.Management;
using System.Net;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.RegularExpressions;

namespace SnapDns.Service.Services
{
    /// <summary>
    /// Manages Operating System DNS settings.
    /// Handles Platform-Specific logic (WMI for Windows, nmcli for Linux, networksetup for macOS).
    /// </summary>
    public partial class SystemDnsService(ILogger<SystemDnsService> logger, DnsProxyService dnsProxy)
    {

        // --- REGEX DEFINITIONS ---
        [GeneratedRegex(@"^(\S.*?)\s{2,}", RegexOptions.Compiled)]
        private static partial Regex NameRegex();

        [GeneratedRegex(@"dev\s+(\S+)", RegexOptions.IgnoreCase | RegexOptions.Compiled)]
        private static partial Regex InterfaceMatchRegex();

        [GeneratedRegex(@"GENERAL\.CONNECTION:\s+(.*)", RegexOptions.Compiled)]
        private static partial Regex ConnectionMatchRegex();

        [GeneratedRegex(@"IP4\.DNS\[\d+\]:\s+(.*)", RegexOptions.Compiled)]
        private static partial Regex DnsRegex();

        // ==========================================
        // PUBLIC API (Mapped to PipeCommands)
        // ==========================================

        public PipeResponse GetNetworkAdapters()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return GetNetworkAdaptersWindows();
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return GetNetworkAdaptersMacOs();
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return GetNetworkAdaptersLinux();
            return new PipeResponse { Success = false, Message = "Unsupported operating system." };
        }

        public PipeResponse GetPreferredAdapterName()
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return GetPreferredAdapterNameWindows();
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return GetPreferredAdapterNameMacOs();
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return GetPreferredAdapterNameLinux();
            return new PipeResponse { Success = false, Message = "Unsupported operating system." };
        }

        public PipeResponse GetCurrentDnsConfiguration(string adapterName)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return GetCurrentDnsConfigurationWindows(adapterName);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return GetCurrentDnsConfigurationMacOs(adapterName);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return GetCurrentDnsConfigurationLinux(adapterName);
            return new PipeResponse { Success = false, Message = $"Unsupported operating system for adapter {adapterName}." };
        }

        public PipeResponse ApplyDnsConfiguration(string adapterName, DnsConfiguration configuration)
        {
            // 1. Check if DoH (DNS over HTTPS) is requested
            bool isDoh = !string.IsNullOrWhiteSpace(configuration.DohUrl);

            if (isDoh)
            {
                logger.LogInformation("Applying DoH Mode via Proxy: {Url}", configuration.DohUrl);

                try
                {
                    // Start Proxy (Synchronous wait to ensure bootstrap completes before OS switch)
                    dnsProxy.StartAsync(configuration.DohUrl).Wait();
                }
                catch (Exception ex)
                {
                    return new PipeResponse { Success = false, Message = $"Proxy Start Failed: {ex.InnerException?.Message ?? ex.Message}" };
                }

                // Redirect OS to Localhost
                var proxyConfig = new DnsConfiguration
                {
                    PrimaryDns = "127.0.0.1",
                    SecondaryDns = "", // No secondary allowed for Proxy mode
                    IsDhcp = false
                };

                return ApplyToOs(adapterName, proxyConfig);
            }
            else
            {
                // 2. Standard IP Mode
                logger.LogInformation("Applying Standard DNS Mode.");

                // Ensure proxy is stopped to free up port 53
                dnsProxy.Stop();

                if (string.IsNullOrWhiteSpace(configuration.PrimaryDns))
                    return new PipeResponse { Success = false, Message = "Primary DNS address is required." };

                return ApplyToOs(adapterName, configuration);
            }
        }

        public PipeResponse ResetToDhcp(string adapterName)
        {
            // Always stop proxy on reset
            dnsProxy.Stop();

            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return ResetToDhcpWindows(adapterName);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return ResetToDhcpMacOs(adapterName);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return ResetToDhcpLinux(adapterName);
            return new PipeResponse { Success = false, Message = $"Unsupported operating system for adapter {adapterName}." };
        }

        public PipeResponse FlushDns()
        {
            logger.LogInformation("Attempting to Flush DNS Cache...");

            try
            {
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    var (success, output) = ExecuteCommand("cmd.exe", "/c ipconfig /flushdns");
                    if (success) return new PipeResponse { Success = true, Message = "DNS Cache Flushed Successfully." };
                    return new PipeResponse { Success = false, Message = $"Failed: {output}" };
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    ExecuteCommand("/usr/bin/dscacheutil", "-flushcache");
                    ExecuteCommand("/usr/bin/killall", "-HUP mDNSResponder");
                    return new PipeResponse { Success = true, Message = "DNS Cache Flushed Successfully." };
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                {
                    var (s, o) = ExecuteCommand("resolvectl", "flush-caches");
                    if (s) return new PipeResponse { Success = true, Message = "DNS Cache Flushed." };

                    var (s2, o2) = ExecuteCommand("systemd-resolve", "--flush-caches");
                    if (s2) return new PipeResponse { Success = true, Message = "DNS Cache Flushed." };

                    return new PipeResponse { Success = false, Message = "Could not flush DNS (resolvectl/systemd-resolved not found)." };
                }

                return new PipeResponse { Success = false, Message = "Unsupported operating system for Flush DNS." };
            }
            catch (Exception ex)
            {
                return new PipeResponse { Success = false, Message = $"Exception: {ex.Message}" };
            }
        }

        // ==========================================
        // PRIVATE HELPERS & OS IMPLEMENTATIONS
        // ==========================================

        private PipeResponse ApplyToOs(string adapterName, DnsConfiguration config)
        {
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) return ApplyDnsConfigurationWindows(adapterName, config);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX)) return ApplyDnsConfigurationMacOs(adapterName, config);
            else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux)) return ApplyDnsConfigurationLinux(adapterName, config);
            return new PipeResponse { Success = false, Message = "Unsupported OS" };
        }

        private (bool Success, string Output) ExecuteCommand(string fileName, string arguments)
        {
            try
            {
                using var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = fileName,
                        Arguments = arguments,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                    }
                };

                logger.LogTrace("Executing: {File} {Args}", fileName, arguments);
                process.Start();
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                return (process.ExitCode == 0, output.Trim());
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Exec failed: {File}", fileName);
                return (false, "Exec exception");
            }
        }

        // --- WINDOWS (WMI) ---
        [SupportedOSPlatform("windows")]
        private ManagementObject? GetNetworkAdapterWindows(string adapterName)
        {
            try
            {
                var scope = new ManagementScope("\\\\.\\root\\cimv2");
                scope.Connect();
                string escapedAdapterName = adapterName.Replace("'", "''");
                var configQuery = new SelectQuery($"SELECT * FROM Win32_NetworkAdapterConfiguration WHERE Description='{escapedAdapterName}' AND IPEnabled = TRUE");
                var configSearcher = new ManagementObjectSearcher(scope, configQuery);

                return configSearcher.Get().Cast<ManagementObject>().FirstOrDefault();
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "WMI Error for {Adapter}", adapterName);
                return null;
            }
        }

        [SupportedOSPlatform("windows")]
        public PipeResponse GetNetworkAdaptersWindows()
        {
            logger.LogInformation("Retrieving Windows Network Adapters via WMI.");
            try
            {
                var adapters = new List<string>();
                var scope = new ManagementScope("\\\\.\\root\\cimv2");
                scope.Connect();
                var query = new SelectQuery("SELECT Description FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE");
                var searcher = new ManagementObjectSearcher(scope, query);

                foreach (ManagementObject config in searcher.Get().Cast<ManagementObject>())
                {
                    if (config["Description"] is string description && !string.IsNullOrWhiteSpace(description))
                    {
                        adapters.Add(description);
                    }
                }
                return new PipeResponse { Success = true, Adapters = adapters };
            }
            catch (Exception ex) { return new PipeResponse { Success = false, Message = ex.Message }; }
        }

        [SupportedOSPlatform("windows")]
        public PipeResponse GetPreferredAdapterNameWindows()
        {
            logger.LogInformation("Detecting Preferred Windows Adapter.");
            try
            {
                var scope = new ManagementScope("\\\\.\\root\\cimv2");
                scope.Connect();
                var query = new SelectQuery("SELECT Description FROM Win32_NetworkAdapterConfiguration WHERE DefaultIPGateway IS NOT NULL AND IPEnabled = TRUE");
                var searcher = new ManagementObjectSearcher(scope, query);

                if (searcher.Get().Cast<ManagementObject>().FirstOrDefault() is ManagementObject preferredConfig)
                {
                    if (preferredConfig["Description"] is string adapterName)
                    {
                        return new PipeResponse { Success = true, PreferredAdapterName = adapterName };
                    }
                }
                return new PipeResponse { Success = false, Message = "No active adapter found." };
            }
            catch (Exception ex) { return new PipeResponse { Success = false, Message = ex.Message }; }
        }

        [SupportedOSPlatform("windows")]
        public PipeResponse GetCurrentDnsConfigurationWindows(string adapterName)
        {
            var adapterConfig = GetNetworkAdapterWindows(adapterName);
            if (adapterConfig == null) return new PipeResponse { Success = false, Message = $"Adapter '{adapterName}' not found." };

            try
            {
                DnsConfiguration currentConfig;
                if (adapterConfig["DNSServerSearchOrder"] is string[] dnsServers && dnsServers.Length > 0)
                {
                    currentConfig = new DnsConfiguration
                    {
                        Id = Guid.NewGuid(),
                        Name = "Custom",
                        PrimaryDns = dnsServers[0],
                        SecondaryDns = dnsServers.Length > 1 ? dnsServers[1] : string.Empty,
                        IsDhcp = false
                    };
                }
                else
                {
                    currentConfig = new DnsConfiguration { Id = Guid.NewGuid(), Name = "DHCP", IsDhcp = true };
                }
                return new PipeResponse { Success = true, Configuration = currentConfig };
            }
            catch (Exception ex) { return new PipeResponse { Success = false, Message = ex.Message }; }
        }

        [SupportedOSPlatform("windows")]
        public PipeResponse ApplyDnsConfigurationWindows(string adapterName, DnsConfiguration configuration)
        {
            var adapterConfig = GetNetworkAdapterWindows(adapterName);
            if (adapterConfig == null) return new PipeResponse { Success = false, Message = $"Adapter '{adapterName}' not found." };

            try
            {
                string[] dnsArray = string.IsNullOrWhiteSpace(configuration.SecondaryDns)
                    ? [configuration.PrimaryDns]
                    : [configuration.PrimaryDns, configuration.SecondaryDns];

                ManagementBaseObject setDnsParams = adapterConfig.GetMethodParameters("SetDNSServerSearchOrder");
                setDnsParams["DNSServerSearchOrder"] = dnsArray;
                ManagementBaseObject? resultObject = adapterConfig.InvokeMethod("SetDNSServerSearchOrder", setDnsParams, null) as ManagementBaseObject;

                uint result = (resultObject?["ReturnValue"] != null) ? Convert.ToUInt32(resultObject["ReturnValue"]) : 1;

                if (result == 0) return new PipeResponse { Success = true, Message = "DNS configuration applied." };
                else return new PipeResponse { Success = false, Message = $"WMI Error: {result}" };
            }
            catch (Exception ex) { return new PipeResponse { Success = false, Message = ex.Message }; }
        }

        [SupportedOSPlatform("windows")]
        public PipeResponse ResetToDhcpWindows(string adapterName)
        {
            var adapterConfig = GetNetworkAdapterWindows(adapterName);
            if (adapterConfig == null) return new PipeResponse { Success = false, Message = $"Adapter '{adapterName}' not found." };

            try
            {
                ManagementBaseObject resetDnsParams = adapterConfig.GetMethodParameters("SetDNSServerSearchOrder");
                resetDnsParams["DNSServerSearchOrder"] = null;
                ManagementBaseObject? resultObject = adapterConfig.InvokeMethod("SetDNSServerSearchOrder", resetDnsParams, null) as ManagementBaseObject;

                uint result = (resultObject?["ReturnValue"] != null) ? Convert.ToUInt32(resultObject["ReturnValue"]) : 1;

                if (result == 0) return new PipeResponse { Success = true, Message = "DNS reset to DHCP." };
                else return new PipeResponse { Success = false, Message = $"WMI Error: {result}" };
            }
            catch (Exception ex) { return new PipeResponse { Success = false, Message = ex.Message }; }
        }

        // --- MACOS ---
        [SupportedOSPlatform("osx")]
        public PipeResponse GetNetworkAdaptersMacOs()
        {
            logger.LogInformation("Listing macOS network services.");
            var (success, output) = ExecuteCommand("/usr/sbin/networksetup", "-listallnetworkservices");
            if (!success) return new PipeResponse { Success = false, Message = output };
            var adapters = output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                .Skip(1).Select(l => l.TrimStart('*').Trim())
                .Where(s => !s.Contains("Bluetooth")).ToList();
            return new PipeResponse { Success = true, Adapters = adapters };
        }

        [SupportedOSPlatform("osx")]
        public PipeResponse GetPreferredAdapterNameMacOs()
        {
            // Simplified logic: Check route to 8.8.8.8 to find active interface
            var (s, o) = ExecuteCommand("sh", "-c \"route get 8.8.8.8 | grep interface\"");
            if (s && !string.IsNullOrWhiteSpace(o))
            {
                var interfaceName = o.Split(':')[1].Trim();
                logger.LogInformation("macOS Active Interface: {If}", interfaceName);
                return new PipeResponse { Success = true, PreferredAdapterName = interfaceName };
            }
            return new PipeResponse { Success = false, Message = "Could not determine active interface." };
        }

        [SupportedOSPlatform("osx")]
        public PipeResponse GetCurrentDnsConfigurationMacOs(string adapterName)
        {
            var (success, output) = ExecuteCommand("/usr/sbin/networksetup", $"-getdnsservers \"{adapterName}\"");
            if (!success) return new PipeResponse { Success = false, Message = output };

            // Logic to parse output (Same as previous, just logged)
            var dnsServers = new List<string>();
            foreach (var line in output.Split('\n')) if (IPAddress.TryParse(line.Trim(), out _)) dnsServers.Add(line.Trim());

            bool isDhcp = dnsServers.Count == 0;
            var config = new DnsConfiguration
            {
                Id = Guid.NewGuid(),
                IsDhcp = isDhcp,
                PrimaryDns = dnsServers.FirstOrDefault() ?? "",
                SecondaryDns = dnsServers.Skip(1).FirstOrDefault() ?? ""
            };

            return new PipeResponse { Success = true, Configuration = config };
        }

        [SupportedOSPlatform("osx")]
        public PipeResponse ApplyDnsConfigurationMacOs(string adapterName, DnsConfiguration configuration)
        {
            string[] dnsArray = string.IsNullOrWhiteSpace(configuration.SecondaryDns) ? [configuration.PrimaryDns] : [configuration.PrimaryDns, configuration.SecondaryDns];
            string args = string.Join(" ", dnsArray);
            var (s, o) = ExecuteCommand("/usr/sbin/networksetup", $"-setdnsservers \"{adapterName}\" {args}");
            return s ? new PipeResponse { Success = true } : new PipeResponse { Success = false, Message = o };
        }

        [SupportedOSPlatform("osx")]
        public PipeResponse ResetToDhcpMacOs(string adapterName)
        {
            var (s, o) = ExecuteCommand("/usr/sbin/networksetup", $"-setdnsservers \"{adapterName}\" empty");
            return s ? new PipeResponse { Success = true } : new PipeResponse { Success = false, Message = o };
        }

        // --- LINUX ---
        [SupportedOSPlatform("linux")]
        public PipeResponse GetNetworkAdaptersLinux()
        {
            var (s, o) = ExecuteCommand("/usr/bin/nmcli", "connection show --active");
            if (!s) return new PipeResponse { Success = false, Message = o };
            var adapters = o.Split('\n').Skip(1).Select(l => l.Split(' ')[0]).ToList();
            return new PipeResponse { Success = true, Adapters = adapters };
        }

        [SupportedOSPlatform("linux")]
        public PipeResponse GetPreferredAdapterNameLinux()
        {
            var (s, o) = ExecuteCommand("/usr/sbin/ip", "route get 1.1.1.1");
            if (!s) return new PipeResponse { Success = false, Message = "Failed to get route." };
            var match = InterfaceMatchRegex().Match(o);
            return match.Success
                ? new PipeResponse { Success = true, PreferredAdapterName = match.Groups[1].Value.Trim() }
                : new PipeResponse { Success = false, Message = "No primary interface." };
        }

        [SupportedOSPlatform("linux")]
        public PipeResponse GetCurrentDnsConfigurationLinux(string adapterName)
        {
            // Simplified Linux retrieval (nmcli device show)
            var (s, o) = ExecuteCommand("/usr/bin/nmcli", $"device show \"{adapterName}\"");
            if (!s) return new PipeResponse { Success = false, Message = o };

            // Extract DNS lines
            var dnsList = new List<string>();
            var match = DnsRegex().Match(o);
            while (match.Success) { dnsList.Add(match.Groups[1].Value.Trim()); match = match.NextMatch(); }

            return new PipeResponse { Success = true, Configuration = new DnsConfiguration { PrimaryDns = dnsList.FirstOrDefault() ?? "", IsDhcp = dnsList.Count == 0 } };
        }

        [SupportedOSPlatform("linux")]
        public PipeResponse ApplyDnsConfigurationLinux(string adapterName, DnsConfiguration configuration)
        {
            string dnsList = string.IsNullOrWhiteSpace(configuration.SecondaryDns) ? configuration.PrimaryDns : $"{configuration.PrimaryDns},{configuration.SecondaryDns}";
            var (s, o) = ExecuteCommand("/usr/bin/nmcli", $"con mod \"{adapterName}\" ipv4.dns \"{dnsList}\" ipv4.ignore-auto-dns yes");
            if (s) ExecuteCommand("/usr/bin/nmcli", $"con up \"{adapterName}\""); // Apply
            return s ? new PipeResponse { Success = true } : new PipeResponse { Success = false, Message = o };
        }

        [SupportedOSPlatform("linux")]
        public PipeResponse ResetToDhcpLinux(string adapterName)
        {
            var (s, o) = ExecuteCommand("/usr/bin/nmcli", $"con mod \"{adapterName}\" ipv4.dns \"\" ipv4.ignore-auto-dns no");
            if (s) ExecuteCommand("/usr/bin/nmcli", $"con up \"{adapterName}\"");
            return s ? new PipeResponse { Success = true } : new PipeResponse { Success = false, Message = o };
        }
    }
}