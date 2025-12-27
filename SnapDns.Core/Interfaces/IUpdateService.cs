using System.Threading.Tasks;

namespace SnapDns.Core.Interfaces;

/// <summary>
/// Defines the contract for checking for application updates.
/// </summary>
public interface IUpdateService
{
    /// <summary>
    /// Checks GitHub (or other source) for a newer release.
    /// </summary>
    /// <returns>The URL to the release page (or installer asset) if an update is found; otherwise null.</returns>
    Task<string?> CheckForUpdateAsync();
    /// <summary>
    /// Downlaods the installer file
    /// </summary>
    Task DownloadInstallerAsync(string url, string destinationPath, IProgress<double> progress);


    /// <summary>
    /// Returns the current application version (e.g. "1.0.0").
    /// </summary>
    string CurrentVersion { get; }
}