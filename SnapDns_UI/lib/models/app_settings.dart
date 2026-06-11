class AppSettings {
  bool runOnStartup;
  bool minimizeToTray;
  bool showNotifications;
  bool autoFlush; // NEW
  bool launchHidden; // NEW
  bool verifyConnection;
  String theme;
  String accentColor;

  AppSettings({
    this.runOnStartup = false,
    this.minimizeToTray = true,
    this.showNotifications = true,
    this.autoFlush = true,
    this.launchHidden = false,
    this.verifyConnection = false,
    this.theme = "Dark",
    this.accentColor = "#00C8C8",
  });

  Map<String, dynamic> toJson() => {
    'runOnStartup': runOnStartup,
    'minimizeToTray': minimizeToTray,
    'showNotifications': showNotifications,
    'autoFlush': autoFlush,
    'launchHidden': launchHidden,
    'verifyConnection': verifyConnection,
    'theme': theme,
    'accentColor': accentColor,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    runOnStartup: json['runOnStartup'] ?? false,
    minimizeToTray: json['minimizeToTray'] ?? true,
    showNotifications: json['showNotifications'] ?? true,
    autoFlush: json['autoFlush'] ?? true,
    launchHidden: json['launchHidden'] ?? false,
    verifyConnection: json['verifyConnection'] ?? false,
    theme: json['theme'] ?? "Dark",
    accentColor: json['accentColor'] ?? "#00C8C8",
  );
}
