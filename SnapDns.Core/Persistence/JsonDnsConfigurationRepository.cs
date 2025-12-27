using SnapDns.Core.Interfaces;
using SnapDns.Core.Models;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace SnapDns.Core.Persistence;

/// <summary>
/// Handles loading and saving of the list of DnsConfiguration objects using a local JSON file.
/// Location: %LOCALAPPDATA%/SnapDns/profiles.json
/// </summary>
public class JsonDnsConfigurationRepository : IDnsConfigurationRepository
{
    private readonly string _filePath;
    private readonly JsonSerializerOptions _serializerOptions = new() { WriteIndented = true };

    public JsonDnsConfigurationRepository()
    {
        // Local Data (Profiles might be machine specific or large)
        var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var snapDnsDirectory = Path.Combine(appDataPath, "SnapDns");

        if (!Directory.Exists(snapDnsDirectory))
        {
            Directory.CreateDirectory(snapDnsDirectory);
        }

        _filePath = Path.Combine(snapDnsDirectory, "profiles.json");
    }

    /// <inheritdoc />
    public async Task<List<DnsConfiguration>> LoadAllAsync()
    {
        if (!File.Exists(_filePath))
        {
            return [];
        }

        try
        {
            var jsonString = await File.ReadAllTextAsync(_filePath);
            return JsonSerializer.Deserialize<List<DnsConfiguration>>(jsonString) ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <inheritdoc />
    public async Task<bool> SaveAllAsync(List<DnsConfiguration> configurations)
    {
        try
        {
            var jsonString = JsonSerializer.Serialize(configurations, _serializerOptions);
            await File.WriteAllTextAsync(_filePath, jsonString);
            return true;
        }
        catch
        {
            return false;
        }
    }
}