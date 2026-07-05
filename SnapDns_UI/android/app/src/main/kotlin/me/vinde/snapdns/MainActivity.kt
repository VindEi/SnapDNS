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
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                        result.success(false)
                    } else {
                        val resolvedIps: List<String>? = call.argument<List<String>>("resolvedIps")
                        startDnsVpn(
                            call.argument<String>("primaryDns") ?: "1.1.1.1",
                            call.argument<String>("secondaryDns"),
                            call.argument<String>("privateDns"),
                            call.argument<String>("dohUrl"),
                            call.argument<String>("hostName"),
                            resolvedIps
                        )
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

    private fun startDnsVpn(primary: String, secondary: String?, privateDns: String?, dohUrl: String?, hostName: String?, resolvedIps: List<String>?) {
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