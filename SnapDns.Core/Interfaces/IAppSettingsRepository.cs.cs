using SnapDns.Core.Models;
using System.Threading.Tasks;

namespace SnapDns.Core.Interfaces;

/// <summary>
/// Defines the contract for managing the persistence of AppSettings.
/// </summary>
public interface IAppSettingsRepository
{
    /// <summary>
    /// Loads the application settings from the persistence store.
    /// If no settings are found, a default instance is returned.
    /// </summary>
    /// <returns>The loaded AppSettings object.</returns>
    Task<AppSettings> LoadSettingsAsync();

    /// <summary>
    /// Saves the given application settings to the persistence store.
    /// </summary>
    /// <param name="settings">The AppSettings object to save.</param>
    /// <returns>True if the save was successful, false otherwise.</returns>
    Task<bool> SaveSettingsAsync(AppSettings settings);
}