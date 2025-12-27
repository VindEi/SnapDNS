namespace SnapDns.Core.Models;

/// <summary>
/// Represents the user-configurable application settings.
/// </summary>
public class AppSettings
{
    // --- General ---
    public bool RunOnStartup { get; set; } = false;
    public bool MinimizeToTray { get; set; } = true;
    public bool ShowNotifications { get; set; } = true;

    // --- Network ---
    public bool VerifyConnection { get; set; } = false;
    public bool ApplyToAllAdapters { get; set; } = false;

    // --- Appearance ---
    public string Theme { get; set; } = "Dark";
}