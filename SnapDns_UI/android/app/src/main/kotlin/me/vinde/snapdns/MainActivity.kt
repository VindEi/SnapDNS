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
                    val primary = call.argument<String>(SnapDnsConstants.KEY_PRIMARY_DNS) ?: SnapDnsConstants.DEFAULT_PRIMARY_DNS
                    val secondary = call.argument<String>(SnapDnsConstants.KEY_SECONDARY_DNS)
                    val privateDns = call.argument<String>(SnapDnsConstants.KEY_PRIVATE_DNS)
                    val dohUrl = call.argument<String>(SnapDnsConstants.KEY_DOH_URL)
                    val hostName = call.argument<String>(SnapDnsConstants.KEY_HOST_NAME)
                    val resolvedIps: List<String>? = call.argument<List<String>>(SnapDnsConstants.KEY_RESOLVED_IPS)

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
            val prefs = getSharedPreferences(SnapDnsConstants.PREFS_NAME, MODE_PRIVATE)
            val primary = prefs.getString(SnapDnsConstants.KEY_PRIMARY_DNS, SnapDnsConstants.DEFAULT_PRIMARY_DNS) ?: SnapDnsConstants.DEFAULT_PRIMARY_DNS
            val secondary = prefs.getString(SnapDnsConstants.KEY_SECONDARY_DNS, null)
            val privateDns = prefs.getString(SnapDnsConstants.KEY_PRIVATE_DNS, null)
            val dohUrl = prefs.getString(SnapDnsConstants.KEY_DOH_URL, null)
            val hostName = prefs.getString(SnapDnsConstants.KEY_HOST_NAME, null)
            val resolvedIpsSet = prefs.getStringSet(SnapDnsConstants.KEY_RESOLVED_IPS, null)
            val resolvedIps = resolvedIpsSet?.let { ArrayList(it) }

            startDnsVpn(primary, secondary, privateDns, dohUrl, hostName, resolvedIps)
        }
    }

    private fun savePrefs(primary: String, secondary: String?, privateDns: String?, dohUrl: String?, hostName: String?, resolvedIps: List<String>?) {
        val prefs = getSharedPreferences(SnapDnsConstants.PREFS_NAME, MODE_PRIVATE)
        prefs.edit().apply {
            putString(SnapDnsConstants.KEY_PRIMARY_DNS, primary)
            putString(SnapDnsConstants.KEY_SECONDARY_DNS, secondary)
            putString(SnapDnsConstants.KEY_PRIVATE_DNS, privateDns)
            putString(SnapDnsConstants.KEY_DOH_URL, dohUrl)
            putString(SnapDnsConstants.KEY_HOST_NAME, hostName)
            if (resolvedIps != null) {
                putStringSet(SnapDnsConstants.KEY_RESOLVED_IPS, HashSet(resolvedIps))
            } else {
                remove(SnapDnsConstants.KEY_RESOLVED_IPS)
            }
            apply()
        }
    }

    private fun startDnsVpn(primary: String, secondary: String?, privateDns: String?, dohUrl: String?, hostName: String?, resolvedIps: List<String>?) {
        val serviceIntent = SnapDnsConstants.buildVpnIntent(this, primary, secondary, privateDns, dohUrl, hostName, resolvedIps)
        startService(serviceIntent)
    }
}
