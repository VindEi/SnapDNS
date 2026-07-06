package me.vinde.snapdns

import android.content.Context
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.util.ArrayList

class SnapDnsTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (DnsVpnService.isRunning) {
            val stopIntent = Intent(this, DnsVpnService::class.java).apply {
                action = "STOP"
            }
            startService(stopIntent)
        } else {
            val prefs = getSharedPreferences("SnapDnsPrefs", Context.MODE_PRIVATE)
            val primary = prefs.getString("primaryDns", "1.1.1.1") ?: "1.1.1.1"
            val secondary = prefs.getString("secondaryDns", null)
            val privateDns = prefs.getString("privateDns", null)
            val dohUrl = prefs.getString("dohUrl", null)
            
            // FIX: Load pre-resolved host details to prevent loopback deadlocks on Quick Tile toggles
            val hostName = prefs.getString("hostName", null)
            val resolvedIpsSet = prefs.getStringSet("resolvedIps", null)
            val resolvedIps = resolvedIpsSet?.let { ArrayList(it) }

            val startIntent = Intent(this, DnsVpnService::class.java).apply {
                putExtra("primaryDns", primary)
                putExtra("secondaryDns", secondary)
                putExtra("privateDns", privateDns)
                putExtra("dohUrl", dohUrl)
                putExtra("hostName", hostName)
                if (resolvedIps != null) {
                    putStringArrayListExtra("resolvedIps", resolvedIps)
                }
            }
            startService(startIntent)
        }

        try {
            Thread.sleep(150)
        } catch (e: Exception) {
            // Handled
        }
        
        updateTileState()
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val running = DnsVpnService.isRunning

        if (running) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "SnapDNS (On)"
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "SnapDNS (Off)"
        }
        tile.updateTile()
    }
}