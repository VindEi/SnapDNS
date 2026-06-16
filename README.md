# ⚡ SnapDNS

<p align="center">
  <img src="https://img.shields.io/badge/status-active-success" alt="Status: Active">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License: GPL-3.0">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Android%20%7C%20Linux%20%7C%20macOS-lightgrey" alt="Platforms">
  <img src="https://img.shields.io/badge/framework-Flutter%20%7C%20.NET%2010-02569B" alt="Frameworks: Flutter & .NET">
</p>

<p align="center">
  <img src="SnapDns_UI/assets/SnapDns.png" alt="SnapDNS Logo" width="128" height="128" />
</p>

<p align="center">
  <b>A clean, simple, and beautiful DNS manager for your desktop and phone.</b><br>
  Switch your DNS profiles instantly, check your connection speeds, and customize the interface to look exactly how you want. No annoying pop-ups, no complicated setups—just a seamless experience.
</p>

---

## ✨ Features

* 🔌 **Universal DNS Support:** Easily switch between IPv4, IPv6, DNS-over-HTTPS (DoH), and DNS-over-TLS (DoT).
* 📱 **Android Quick Toggle:** Control your DNS directly from your phone's notification bar with a custom Quick Settings tile.
* 📋 **1-Click Auto-Fill:** Just copy any DNS address or sharing link, hit "Auto-Fill" in the editor, and the app instantly configures it for you.
* 💾 **Custom Profile Manager:** Build and edit your own list of servers. Add them manually, import .json backups, and drag-and-drop to reorder them.


* 🗂️ **Customizable Looks:** Full Dark/Light mode support with customizable accent colors. The app's tray icon dynamically changes color to match your chosen style.

---

## 📸 Screenshots

<p align="center">
  <img src="SnapDns_UI/assets/snapdns_main_dark.png" width="250" alt="Main Page">
  <img src="SnapDns_UI/assets/snapdns_profile_dark.png" width="250" alt="Profiles List">
  <img src="SnapDns_UI/assets/snapdns_settings_dark.png" width="250" alt="Settings Menu">
</p>

---

## 📥 Downloads

| OS | Format | Description |
| :--- | :--- | :--- |
| **Windows 10/11** | `.exe` (Installer) | Installs both the app and the background system service. *(Recommended)* |
| **Windows 10/11** | `.zip` (Portable) | Standalone portable folder. Requires manual service setup. |
| **macOS / Linux** | `.zip` (Portable) | Standalone app folders for macOS and Linux users. |
| **Android** | `.apk` | Standard Android installer. Requires Android 7.0+. |

---

## 🚀 Installation & Setup

### Windows (Desktop)
1. Download `SnapDNS_Windows_x64_Portable.zip` from the Releases section.
2. Extract the archive.
3. Right-click `install_windows.bat` and select **"Run as Administrator"** (this sets up the background service so you can change your DNS instantly without Windows throwing those annoying pop-ups).
4. Launch `snapdns.exe` and enjoy!

### macOS / Linux
1. Download the portable archive for your platform.
2. Extract the files.
3. Open a terminal inside the extracted directory and run the installer:
   ```bash
   # On Linux
   sudo ./install_linux.sh

   # On macOS
   sudo ./install_mac.command
   ```
4. Double-click the `snapdns` app to launch it.

### Android (Mobile)
1. Download `SnapDNS_Android_arm64.apk` (or matching file for your device) to your phone.
2. Install the APK (you may need to allow "Install from Unknown Sources" if prompted).
3. Select a profile and click **Connect**. Grant the system permission to run the local tunnel when asked.
4. *(Optional)* Pull down your notification bar, edit your Quick Tiles, and add the **SnapDNS** tile for instant toggling!

---

## <details><summary>🏗️ How It Works</summary>

SnapDNS uses a decoupled architecture to separate unprivileged user interactions from elevated system network configuration commands:

```text
       [ SnapDNS UI (Flutter User-Space) ]
                       │
             (Isolate-Offloaded FFI)
                       │
       (IPC: Named Pipes / Unix Sockets)  <--- Mutex-queued sequential channels
                       │
       [ SnapDNS Service (C# .NET 10 System Daemon) ]
                       │
     (Modifies Network Hardware Adapter Configs)
```

### Advanced Implementation Details:
* **Background Isolate Offloading:** On Windows, synchronous Win32 FFI operations are executed inside a background Dart `Isolate.run()` to prevent FFI blocks or retries from locking the main UI thread.
* **Non-Blocking Mutex Queueing:** The Dart IPC client utilizes an asynchronous mutex (`_SimpleMutex`) to queue all pipeline commands sequentially, eliminating overlapping socket writes.
* **systemd Sandbox Bypass:** On Linux, .NET NamedPipes compile natively as Unix Domain Sockets. To prevent `systemd` private sandboxing (`PrivateTmp=true`) from blocking client-service communication, the socket is bound to a rooted path (`/var/run/snapdns.sock`) with permissive `UnixFileMode` access rules.
* **Self-Healing UDP Listeners:** The background C# DNS proxy on Port 53 is built with a self-healing UDP socket listener. If a hardware sleep/wake transition or network adapter swap occurs, the service automatically re-binds a new socket and continues listening.
* **Circular Lookup Deadlock Prevention:** On Android, starting a secure domain-based tunnel (like `one.one.one.one`) creates a resolution deadlock. The VPN tunnel configuration automatically appends public bootstrap fallback IPs (`1.1.1.1` and `8.8.8.8`) to the V2Ray core so it can resolve its own secure endpoint on boot.

</details>

---

## <details><summary>🏗️ Building from Source</summary>

### Prerequisites
* Flutter SDK (>= 3.22.0)
* .NET 10.0 SDK
* C++ Desktop Development workloads (Visual Studio 2022 on Windows, Clang/GCC on Linux, Xcode on macOS)

### 1. Compile the Standalone background Service (C#)
```bash
# For Windows
dotnet publish SnapDns.Service.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true

# For Linux
dotnet publish SnapDns.Service.csproj -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true

# For macOS (Apple Silicon)
dotnet publish SnapDns.Service.csproj -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true
```

### 2. Compile the Flutter User Interface
```bash
# Move to the UI directory
cd ../SnapDns_UI
flutter pub get

# Build target
flutter build windows --release --build-name 2.0.0 --build-number 1
# OR
flutter build linux --release --build-name 2.0.0 --build-number 1
# OR
flutter build macos --release --build-name 2.0.0 --build-number 1
# OR
flutter build apk --release --split-per-abi --build-name 2.0.0 --build-number 1
```

</details>

---

## 🤝 Contributing

We welcome contributions! If you'd like to help improve the project:

1. Fork the repository.
2. Create a feature branch (`git checkout -b feat/amazing-feature`).
3. Commit your changes (`git commit -m 'Add amazing feature'`).
4. Push to the branch (`git push origin feat/amazing-feature`).
5. Open a Pull Request.

---
## 🛠️ Troubleshooting & Support

If you run into any issues, try these simple steps first:

* **"Service Offline" on Windows:** Right-click the `install_windows.bat` file in your SnapDNS folder and click **Run as Administrator** again to re-register the background system service.
* **DNS not changing on macOS/Linux:** Make sure you ran the installation script (`install_linux.sh` or `install_mac.command`) with `sudo` in your terminal to register the background service.
* **VPN disconnects on Android:** If your connection drops, open the app, disconnect, and connect again. Your phone's system may have closed the background service to save battery.
* **No Internet after connecting:** Go to Settings and click **Manual Cache Flush** to clear your system's DNS cache, or click **Restart System Service** to reboot the background daemon.

Still having trouble? Please open an **Issue** on this repository with your operating system details and any error messages displayed by the app.

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** - see the [LICENSE](LICENSE) file for details.