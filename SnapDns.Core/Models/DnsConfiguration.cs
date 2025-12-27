using CommunityToolkit.Mvvm.ComponentModel;
using System;
using System.Text.Json.Serialization;

namespace SnapDns.Core.Models;

/// <summary>
/// Represents a DNS configuration profile (e.g. "Google DNS", "Cloudflare").
/// Includes UI state properties for display logic.
/// </summary>
public partial class DnsConfiguration : ObservableObject
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;

    [ObservableProperty] private bool _isDhcp = false;
    [ObservableProperty] private string _primaryDns = string.Empty;
    [ObservableProperty] private string _secondaryDns = string.Empty;
    [ObservableProperty] private string _dohUrl = string.Empty;

    // --- UI States (Not Persisted) ---

    [JsonIgnore]
    [ObservableProperty]
    private bool _isExpanded;

    [JsonIgnore]
    [ObservableProperty]
    private bool _confirmDelete;

    [JsonIgnore]
    [ObservableProperty]
    private bool _isActive;

    [JsonIgnore]
    [ObservableProperty]
    private bool _isInputMatch;

    // --- Latency Data ---

    [JsonIgnore]
    [ObservableProperty]
    private long _latencyMs = -1; // -1 means checking or failed

    [JsonIgnore]
    [ObservableProperty]
    private bool _showLatencyUI;
}