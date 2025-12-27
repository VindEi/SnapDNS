using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using SnapDns.Core.Interfaces;
using SnapDns.Core.Models;
using SnapDns.Core.Persistence;
using SnapDns.Core.Services;
using System.Net.NetworkInformation;

namespace SnapDns.Console
{
    public class Program
    {
        private static IHost? _host;
        private static readonly List<DnsConfiguration> _testDnsConfigurations =
        [
            new DnsConfiguration { Name = "Cloudflare (1.1.1.1)", PrimaryDns = "1.1.1.1", SecondaryDns = "1.0.0.1" },
            new DnsConfiguration { Name = "Google (8.8.8.8)", PrimaryDns = "8.8.8.8", SecondaryDns = "8.8.4.4" },
            new DnsConfiguration { Name = "AdGuard (94.140.14.14)", PrimaryDns = "94.140.14.14", SecondaryDns = "94.140.14.15" },
            new DnsConfiguration { Name = "Custom", PrimaryDns = "", SecondaryDns = "" }
        ];

        public static async Task Main(string[] args)
        {
            // Build the Dependency Injection container
            _host = Host.CreateDefaultBuilder(args)
                .ConfigureServices((context, services) =>
                {
                    // Register Core Repositories and Services
                    services.AddSingleton<IDnsConfigurationRepository, JsonDnsConfigurationRepository>();
                    services.AddSingleton<IAppSettingsRepository, JsonAppSettingsRepository>();
                    services.AddSingleton<IDnsService, DnsService>();
                })
                .Build();

            // Run the main application loop
            await RunMenuLoopAsync();
        }

        private static async Task RunMenuLoopAsync()
        {
            var dnsService = _host!.Services.GetRequiredService<IDnsService>();
            System.Console.Clear();
            System.Console.WriteLine("=== SnapDNS Console Test Runner ===");
            System.Console.ForegroundColor = ConsoleColor.Red;
            System.Console.WriteLine("NOTE: This application should be run as Administrator for full functionality!");
            System.Console.ResetColor();

            // 1. Adapter Selection
            string? selectedAdapter = await SelectAdapterAsync(dnsService);
            if (selectedAdapter == null)
            {
                System.Console.WriteLine("\nNo suitable network adapter found. Exiting.");
                return;
            }

            // 2. Main Menu Loop
            while (true)
            {
                System.Console.Clear();
                System.Console.WriteLine("=== SnapDNS Console Test Runner ===");
                System.Console.WriteLine($"- Active Adapter: {selectedAdapter}");
                System.Console.WriteLine("-----------------------------------");
                System.Console.WriteLine("1. View Available DNS Configurations and Latency");
                System.Console.WriteLine("2. Apply DNS Configuration");
                System.Console.WriteLine("3. Reset DNS to DHCP (Automatic)");
                System.Console.WriteLine("4. Change Active Adapter");
                System.Console.WriteLine("5. Exit");
                System.Console.Write("\nSelect an option: ");

                var input = System.Console.ReadKey().KeyChar.ToString();
                System.Console.WriteLine(); // Newline after key press

                switch (input)
                {
                    case "1":
                        await ViewLatencyAsync(dnsService);
                        break;
                    case "2":
                        await ApplyDnsAsync(dnsService, selectedAdapter);
                        break;
                    case "3":
                        await ResetDnsAsync(dnsService, selectedAdapter);
                        break;
                    case "4":
                        selectedAdapter = await SelectAdapterAsync(dnsService);
                        break;
                    case "5":
                        return;
                    default:
                        System.Console.WriteLine("Invalid option. Press any key to continue...");
                        System.Console.ReadKey();
                        break;
                }
            }
        }

        private static async Task<string?> SelectAdapterAsync(IDnsService dnsService)
        {
            System.Console.WriteLine("\n--- Available Network Adapters ---");
            var adapters = await dnsService.GetNetworkAdaptersAsync();

            if (adapters.Count == 0)
            {
                System.Console.WriteLine("No active, relevant network adapters found.");
                return null;
            }

            for (int i = 0; i < adapters.Count; i++)
            {
                System.Console.WriteLine($"{i + 1}. {adapters[i]}");
            }

            System.Console.Write("\nEnter adapter number to use: ");
            if (int.TryParse(System.Console.ReadLine(), out int choice) && choice > 0 && choice <= adapters.Count)
            {
                return adapters[choice - 1];
            }
            else
            {
                System.Console.WriteLine("Invalid selection. Press any key to use the preferred adapter...");
                System.Console.ReadKey();
                return await dnsService.GetPreferredAdapterNameAsync();
            }
        }

        private static async Task ViewLatencyAsync(IDnsService dnsService)
        {
            System.Console.WriteLine("\n--- DNS Latency Check ---");
            System.Console.WriteLine("Name\t\tPrimary DNS\tSecondary DNS\tLatency (ms)");
            System.Console.WriteLine("-----------------------------------------------------------------");

            foreach (var config in _testDnsConfigurations.Where(c => !string.IsNullOrWhiteSpace(c.PrimaryDns)))
            {
                var latency = await dnsService.CheckLatencyAsync(config);
                var latencyDisplay = latency >= 0 ? $"{latency} ms" : "Timeout/Error";

                // Adjust formatting for alignment
                string name = config.Name.Length > 15 ? config.Name[..15] : config.Name.PadRight(15);

                System.Console.WriteLine($"{name}\t{config.PrimaryDns,-15}\t{config.SecondaryDns,-15}\t{latencyDisplay}");
            }

            System.Console.WriteLine("\nPress any key to return to the menu...");
            System.Console.ReadKey();
        }

        private static async Task ApplyDnsAsync(IDnsService dnsService, string adapterName)
        {
            System.Console.WriteLine("\n--- Apply DNS Configuration ---");
            for (int i = 0; i < _testDnsConfigurations.Count; i++)
            {
                // Displaying 'Custom' without IPs unless user edited it
                string primaryDnsDisplay = string.IsNullOrWhiteSpace(_testDnsConfigurations[i].PrimaryDns) && _testDnsConfigurations[i].Name == "Custom"
                                           ? "(Enter IP)"
                                           : _testDnsConfigurations[i].PrimaryDns;
                System.Console.WriteLine($"{i + 1}. {_testDnsConfigurations[i].Name} ({primaryDnsDisplay})");
            }

            System.Console.Write("\nEnter number of configuration to apply: ");
            if (int.TryParse(System.Console.ReadLine(), out int choice) && choice > 0 && choice <= _testDnsConfigurations.Count)
            {
                var config = _testDnsConfigurations[choice - 1];

                if (config.Name == "Custom")
                {
                    System.Console.Write("Enter Primary DNS: ");
                    config.PrimaryDns = System.Console.ReadLine() ?? "";
                    System.Console.Write("Enter Secondary DNS (optional): ");
                    config.SecondaryDns = System.Console.ReadLine() ?? "";
                }

                if (string.IsNullOrWhiteSpace(config.PrimaryDns))
                {
                    System.Console.WriteLine("Primary DNS cannot be empty. Aborting.");
                }
                else
                {
                    System.Console.WriteLine($"\nApplying {config.Name} to {adapterName}...");
                    bool success = await dnsService.ApplyDnsConfigurationAsync(adapterName, config);
                    System.Console.WriteLine(success ? "SUCCESS: DNS applied via service." : "FAILURE: DNS application failed. Check service logs.");
                }
            }
            else
            {
                System.Console.WriteLine("Invalid selection.");
            }

            System.Console.WriteLine("\nPress any key to return to the menu...");
            System.Console.ReadKey();
        }

        private static async Task ResetDnsAsync(IDnsService dnsService, string adapterName)
        {
            System.Console.Write($"\nAre you sure you want to reset DNS for {adapterName} to DHCP? (y/n): ");
            if (System.Console.ReadKey().KeyChar.ToString().Equals("y", StringComparison.OrdinalIgnoreCase))
            {
                System.Console.WriteLine($"\n\nResetting DNS for {adapterName} to DHCP...");
                bool success = await dnsService.ResetToDhcpAsync(adapterName);
                System.Console.WriteLine(success ? "SUCCESS: DNS reset to DHCP via service." : "FAILURE: DNS reset failed. Check service logs.");
            }
            else
            {
                System.Console.WriteLine("\n\nReset cancelled.");
            }

            System.Console.WriteLine("\nPress any key to return to the menu...");
            System.Console.ReadKey();
        }
    }
}