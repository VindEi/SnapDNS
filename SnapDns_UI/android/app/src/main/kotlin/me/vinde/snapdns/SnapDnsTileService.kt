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
            updateTileState(running = false)
        } else {
            val prefs = getSharedPreferences(SnapDnsConstants.PREFS_NAME, Context.MODE_PRIVATE)
            val primary = prefs.getString(SnapDnsConstants.KEY_PRIMARY_DNS, SnapDnsConstants.DEFAULT_PRIMARY_DNS) ?: SnapDnsConstants.DEFAULT_PRIMARY_DNS
            val secondary = prefs.getString(SnapDnsConstants.KEY_SECONDARY_DNS, null)
            val privateDns = prefs.getString(SnapDnsConstants.KEY_PRIVATE_DNS, null)
            val dohUrl = prefs.getString(SnapDnsConstants.KEY_DOH_URL, null)
            
            // Load pre-resolved host details to prevent loopback deadlocks on Quick Tile toggles
            val hostName = prefs.getString(SnapDnsConstants.KEY_HOST_NAME, null)
            val resolvedIpsSet = prefs.getStringSet(SnapDnsConstants.KEY_RESOLVED_IPS, null)
            val resolvedIps = resolvedIpsSet?.let { ArrayList(it) }

            val startIntent = SnapDnsConstants.buildVpnIntent(
                this, primary, secondary, privateDns, dohUrl, hostName, resolvedIps
            )
            startService(startIntent)
            updateTileState(running = true)
        }
    }

    private fun updateTileState(running: Boolean = DnsVpnService.isRunning) {
        val tile = qsTile ?: return
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
