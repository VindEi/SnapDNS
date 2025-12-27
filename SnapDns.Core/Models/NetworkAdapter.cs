using CommunityToolkit.Mvvm.ComponentModel;

namespace SnapDns.Core.Models;

/// <summary>
/// Represents a network adapter/connection model.
/// </summary>
public partial class NetworkAdapter : ObservableObject
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }

    public string DisplayName => $"{Name} ({Description})";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CurrentStatusDisplay))]
    private DnsConfiguration _currentDnsConfiguration = new();

    public string CurrentStatusDisplay => CurrentDnsConfiguration.IsDhcp
        ? "Automatic DNS"
        : "Manual";
}