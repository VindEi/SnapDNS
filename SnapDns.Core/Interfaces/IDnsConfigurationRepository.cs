using SnapDns.Core.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace SnapDns.Core.Interfaces;

/// <summary>
/// Defines the contract for managing the persistence of DnsConfiguration objects.
/// This includes loading, saving, and querying the collection of configurations.
/// </summary>
public interface IDnsConfigurationRepository
{
    /// <summary>
    /// Loads all saved DNS configurations from the persistence store.
    /// </summary>
    /// <returns>A list of all DnsConfiguration objects.</returns>
    Task<List<DnsConfiguration>> LoadAllAsync();

    /// <summary>
    /// Saves the entire list of DNS configurations to the persistence store,
    /// overwriting the previous contents.
    /// </summary>
    /// <param name="configurations">The full list of configurations to save.</param>
    /// <returns>True if the save was successful, false otherwise.</returns>
    Task<bool> SaveAllAsync(List<DnsConfiguration> configurations);
}