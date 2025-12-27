using SnapDns.Core.Interfaces;
using SnapDns.Core.Models;
using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace SnapDns.Core.Persistence;

/// <summary>
/// Handles loading and saving of the application settings using a local JSON file.
/// Location: %APPDATA%/SnapDns/settings.json
/// </summary>
public class JsonAppSettingsRepository : IAppSettingsRepository
{
    private readonly string _filePath;
    private readonly JsonSerializerOptions _serializerOptions = new() { WriteIndented = true };

    public JsonAppSettingsRepository()
    {
        // Roaming Data (Settings should roam with user)
        var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var snapDnsDirectory = Path.Combine(appDataPath, "SnapDns");

        if (!Directory.Exists(snapDnsDirectory))
        {
            Directory.CreateDirectory(snapDnsDirectory);
        }

        _filePath = Path.Combine(snapDnsDirectory, "settings.json");
    }

    /// <inheritdoc />
    public async Task<AppSettings> LoadSettingsAsync()
    {
        if (!File.Exists(_filePath))
        {
            return new AppSettings();
        }

        try
        {
            var jsonString = await File.ReadAllTextAsync(_filePath);
            return JsonSerializer.Deserialize<AppSettings>(jsonString) ?? new AppSettings();
        }
        catch
        {
            // If corrupt or error, return defaults
            return new AppSettings();
        }
    }

    /// <inheritdoc />
    public async Task<bool> SaveSettingsAsync(AppSettings settings)
    {
        try
        {
            var jsonString = JsonSerializer.Serialize(settings, _serializerOptions);
            await File.WriteAllTextAsync(_filePath, jsonString);
            return true;
        }
        catch
        {
            return false;
        }
    }
}