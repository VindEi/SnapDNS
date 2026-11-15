package me.vinde.snapdns

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService
import java.util.ArrayList

object SnapDnsConstants {
    const val PREFS_NAME = "SnapDnsPrefs"
    const val KEY_PRIMARY_DNS = "primaryDns"
    const val KEY_SECONDARY_DNS = "secondaryDns"
    const val KEY_PRIVATE_DNS = "privateDns"
    const val KEY_DOH_URL = "dohUrl"
    const val KEY_HOST_NAME = "hostName"
    const val KEY_RESOLVED_IPS = "resolvedIps"
    const val DEFAULT_PRIMARY_DNS = "1.1.1.1"

    fun buildVpnIntent(
        context: Context,
        primary: String,
        secondary: String?,
        privateDns: String?,
        dohUrl: String?,
        hostName: String?,
        resolvedIps: List<String>?
    ): Intent {
        return Intent(context, DnsVpnService::class.java).apply {
            putExtra(KEY_PRIMARY_DNS, primary)
            putExtra(KEY_SECONDARY_DNS, secondary)
            putExtra(KEY_PRIVATE_DNS, privateDns)
            putExtra(KEY_DOH_URL, dohUrl)
            putExtra(KEY_HOST_NAME, hostName)
            if (resolvedIps != null) {
                putStringArrayListExtra(KEY_RESOLVED_IPS, ArrayList(resolvedIps))
            }
        }
    }

    fun requestTileUpdate(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                TileService.requestListeningState(
                    context,
                    ComponentName(context, SnapDnsTileService::class.java)
                )
            } catch (_: Exception) {}
        }
    }
}
