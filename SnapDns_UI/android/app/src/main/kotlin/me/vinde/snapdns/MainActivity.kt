package me.vinde.snapdns

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context

class MainActivity: FlutterActivity() {
    private val CHANNEL = "me.vinde.snapdns/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openVpnSettings") {
                try {
                    // Open native Android VPN settings screen
                    val intent = Intent(Settings.ACTION_VPN_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", "Could not open VPN settings", e.message)
                }
            } else if (call.method == "saveLastConfig") {
                // Save the V2Ray JSON to SharedPreferences for the Quick Settings Tile
                val config = call.argument<String>("config")
                val prefs = getSharedPreferences("snapdns_prefs", Context.MODE_PRIVATE)
                prefs.edit().putString("last_config", config).apply()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}