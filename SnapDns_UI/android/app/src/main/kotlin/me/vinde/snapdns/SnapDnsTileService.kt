package me.vinde.snapdns

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.github.blueboytm.flutter_v2ray.v2ray.V2rayController
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService

class SnapDnsTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile
        if (tile != null) {
            // Natively check if any VPN interface is currently active on the device
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = cm.activeNetwork
            val caps = cm.getNetworkCapabilities(activeNetwork)
            val isVpnActive = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ?: false

            tile.state = if (isVpnActive) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val tile = qsTile ?: return
        
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = cm.activeNetwork
        val caps = cm.getNetworkCapabilities(activeNetwork)
        val isVpnActive = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ?: false

        if (isVpnActive) {
            // Stop the VPN Service natively
            try {
                stopService(Intent(this, V2rayVPNService::class.java))
            } catch (e: Exception) {
                V2rayController.StopV2ray(this)
            }
            tile.state = Tile.STATE_INACTIVE
        } else {
            // Read the last connected config from SharedPreferences
            val prefs = getSharedPreferences("snapdns_prefs", Context.MODE_PRIVATE)
            val lastConfig = prefs.getString("last_config", null)
            
            if (lastConfig != null) {
                // PINPOINTED FIX: Match the exact 5-parameter Java signature
                V2rayController.StartV2ray(
                    this,
                    "SnapDns QS",
                    lastConfig,
                    null, // blockedApps
                    null  // bypassSubnets
                )
                tile.state = Tile.STATE_ACTIVE
            } else {
                // If no profile was ever connected, open the app so they can choose one
                val intent = packageManager.getLaunchIntentForPackage(packageName)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivityAndCollapse(intent)
                }
            }
        }
        tile.updateTile()
    }
}