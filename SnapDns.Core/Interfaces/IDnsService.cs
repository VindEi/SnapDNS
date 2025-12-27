using SnapDns.Core.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SnapDns.Core.Interfaces;

/// <summary>
/// Defines the contract for applying DNS configurations, checking network connectivity,
/// and managing network adapters via the privileged service.
/// </summary>
public interface IDnsService
{
    // --- Core DNS Application Functions (Delegated to Service) ---

    /// <summary>
    /// Attempts to apply the DNS settings from the given configuration to the specified adapter.
    /// </summary>
    /// <param name="adapterName">The name/ID of the network adapter to modify.</param>
    /// <param name="configuration">The DnsConfiguration to apply.</param>
    /// <returns>True if the application was successful, false otherwise.</returns>
    Task<bool> ApplyDnsConfigurationAsync(string adapterName, DnsConfiguration configuration);

    /// <summary>
    /// Resets the specified network adapter's DNS settings back to automatic (DHCP).
    /// </summary>
    /// <param name="adapterName">The name/ID of the network adapter to modify.</param>
    /// <returns>True if the reset was successful, false otherwise.</returns>
    Task<bool> ResetToDhcpAsync(string adapterName);

    /// <summary>
    /// Retrieves the current DNS configuration (static IPs or DHCP status) for the specified adapter.
    /// </summary>
    /// <param name="adapterName">The name/ID of the network adapter to query.</param>
    /// <returns>The current DnsConfiguration or null if the adapter is not found.</returns>
    Task<DnsConfiguration?> GetCurrentDnsConfigurationAsync(string adapterName);

    // --- Latency/Utility Functions (Implemented locally or via Service) ---

    /// <summary>
    /// Checks the latency (ping time) to the primary DNS server of a configuration.
    /// </summary>
    /// <param name="configuration">The DnsConfiguration to check.</param>
    /// <returns>The latency in milliseconds, or -1 if the check fails.</returns>
    Task<long> CheckLatencyAsync(DnsConfiguration configuration);

    // --- Adapter Management Functions ---

    /// <summary>
    /// Gets a list of names/IDs for all active and relevant network adapters on the system.
    /// </summary>
    /// <returns>A list of network adapter identifiers.</returns>
    Task<List<string>> GetNetworkAdaptersAsync();

    /// <summary>
    /// Attempts to automatically select the most likely preferred network adapter 
    /// (e.g., the primary connected wired or wireless adapter).
    /// </summary>
    /// <returns>The identifier of the preferred adapter, or null if none can be reliably determined.</returns>
    Task<string?> GetPreferredAdapterNameAsync();

    /// <summary>
    /// Flushes the DNS cache on the system.
    /// </summary>
    /// <returns>True if the flush was successful.</returns>
    Task<bool> FlushDnsAsync();

    /// <summary>
    /// Attempts to start the service asynchronously.
    /// </summary>
    /// <returns>A task that represents the asynchronous operation. The task result is <see langword="true"/> if the service was
    /// started successfully; otherwise, <see langword="false"/>.</returns>
    Task<bool> TryStartServiceAsync();

}