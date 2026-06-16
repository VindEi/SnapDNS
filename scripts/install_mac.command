#!/bin/bash
echo "===================================================="
echo "SnapDNS Service Installer (macOS LaunchDaemon)"
echo "===================================================="

if [ "$EUID" -ne 0 ]; then 
  echo "[ERROR] Please run with sudo in the terminal: sudo ./install_mac.command"
  exit
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
chmod +x "$DIR/SnapDnsService"

# FIX: Aligned internal binary casing to match Xcode/Flutter's default capitalized output (SnapDns)
chmod +x "$DIR/SnapDns.app/Contents/MacOS/SnapDns"

PLIST="/Library/LaunchDaemons/com.vindei.snapdns.plist"

cat <<EOF > $PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vindei.snapdns</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DIR/SnapDnsService</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# FIX: Set strict security ownership and permissions to prevent launchd from rejecting the plist
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl load -w $PLIST
echo "[SUCCESS] Service installed and started! You can now open SnapDns.app."