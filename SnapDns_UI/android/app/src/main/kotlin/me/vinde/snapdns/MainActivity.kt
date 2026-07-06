package me.vinde.snapdns

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList

class MainActivity: FlutterActivity() {
    private val CHANNEL = "me.vinde.snapdns/channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val primary = call.argument<String>("primaryDns") ?: "1.1.1.1"
                    val secondary = call.argument<String>("secondaryDns")
                    val privateDns = call.argument<String>("privateDns")
                    val dohUrl = call.argument<String>("dohUrl")
                    val hostName = call.argument<String>("hostName")
                    val resolvedIps: List<String>? = call.argument<List<String>>("resolvedIps")

                    // FIX: Save configurations immediately so they can be retrieved after the UAC prompt
                    savePrefs(primary, secondary, privateDns, dohUrl, hostName, resolvedIps)

                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                        result.success(false)
                    } else {
                        startDnsVpn(primary, secondary, privateDns, dohUrl, hostName, resolvedIps)
                        result.success(true)
                    }
                }
                "stopVpn" -> {
                    val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
                        action = "STOP"
                    }
                    startService(serviceIntent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // FIX: Automatically start the VPN as soon as first-time authorization is approved
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0 && resultCode == RESULT_OK) {
            val prefs = getSharedPreferences("SnapDnsPrefs", MODE_PRIVATE)
            val primary = prefs.getString("primaryDns", "1.1.1.1") ?: "1.1.1.1"
            val secondary = prefs.getString("secondaryDns", null)
            val privateDns = prefs.getString("privateDns", null)
            val dohUrl = prefs.getString("dohUrl", null)
            val hostName = prefs.getString("hostName", null)
            val resolvedIpsSet = prefs.getStringSet("resolvedIps", null)
            val resolvedIps = resolvedIpsSet?.let { ArrayList(it) }

            startDnsVpn(primary, secondary, privateDns, dohUrl, hostName, resolvedIps)
        }
    }

    private fun savePrefs(primary: String, secondary: String?, privateDns: String?, dohUrl: String?, hostName: String?, resolvedIps: List<String>?) {
        val prefs = getSharedPreferences("SnapDnsPrefs", MODE_PRIVATE)
        prefs.edit().apply {
            putString("primaryDns", primary)
            putString("secondaryDns", secondary)
            putString("privateDns", privateDns)
            putString("dohUrl", dohUrl)
            putString("hostName", hostName)
            if (resolvedIps != null) {
                putStringSet("resolvedIps", HashSet(resolvedIps))
            } else {
                remove("resolvedIps")
            }
            apply()
        }
    }

    private fun startDnsVpn(primary: String, secondary: String?, privateDns: String?, dohUrl: String?, hostName: String?, resolvedIps: List<String>?) {
        val serviceIntent = Intent(this, DnsVpnService::class.java).apply {
            putExtra("primaryDns", primary)
            putExtra("secondaryDns", secondary)
            putExtra("privateDns", privateDns)
            putExtra("dohUrl", dohUrl)
            putExtra("hostName", hostName)
            if (resolvedIps != null) {
                putStringArrayListExtra("resolvedIps", ArrayList(resolvedIps))
            }
        }
        startService(serviceIntent)
    }
}