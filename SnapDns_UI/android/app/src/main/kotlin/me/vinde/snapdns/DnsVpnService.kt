package me.vinde.snapdns

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.content.Intent
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.URL
import java.net.HttpURLConnection
import java.nio.ByteBuffer
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocketFactory

class DnsVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null

    // Thread-safe socket pooling for DoT connection reuse
    private var dotSocket: javax.net.ssl.SSLSocket? = null
    private val dotLock = Any()

    companion object {
        @Volatile
        var isRunning = false

        private val StaticHosts = mapOf(
            "cloudflare-dns.com" to listOf("1.1.1.1", "1.0.0.1"),
            "one.one.one.one" to listOf("1.1.1.1", "1.0.0.1"),
            "dns.google" to listOf("8.8.8.8", "8.8.4.4"),
            "dns.quad9.net" to listOf("9.9.9.9", "149.112.112.112"),
            "dns.adguard-dns.com" to listOf("94.140.14.14", "94.140.15.15"),
            "free.shecan.ir" to listOf("178.22.122.100", "185.51.200.2"),
            "dns.electrotm.org" to listOf("78.157.42.100", "78.157.42.101")
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        val action = intent.action
        if (action == "STOP") {
            stopVpn()
            return START_NOT_STICKY
        }

        val primaryDns = intent.getStringExtra("primaryDns") ?: "1.1.1.1"
        val secondaryDns = intent.getStringExtra("secondaryDns")
        val privateDns = intent.getStringExtra("privateDns")
        val dohUrl = intent.getStringExtra("dohUrl")
        val hostName = intent.getStringExtra("hostName")
        val resolvedIps = intent.getStringArrayListExtra("resolvedIps")

        try {
            stopVpn() 

            val builder = Builder()
                .setSession("SnapDNS")
                .addAddress("10.0.0.2", 24)

            builder.addRoute("10.0.0.1", 32)
            builder.addDnsServer("10.0.0.1")

            vpnInterface = builder.establish()

            vpnThread = Thread {
                runVpnLoop(dohUrl, privateDns, hostName, resolvedIps, primaryDns, secondaryDns)
            }
            vpnThread?.start()

            isRunning = true 
            Log.i("DnsVpnService", "DNS VPN active.")
        } catch (e: Exception) {
            isRunning = false
            Log.e("DnsVpnService", "Failed to start VPN: ${e.message}")
        }

        return START_STICKY
    }

    private fun runVpnLoop(dohUrl: String?, dotHost: String?, hostName: String?, resolvedIps: List<String>?, primaryDns: String, secondaryDns: String?) {
        val fd = vpnInterface?.fileDescriptor ?: return
        val inputStream = FileInputStream(fd)
        val outputStream = FileOutputStream(fd)
        
        val buffer = ByteBuffer.allocate(16384)
        val threadPool = java.util.concurrent.Executors.newFixedThreadPool(8)
        val resolvedIp = resolvedIps?.firstOrNull()

        while (vpnInterface != null && !Thread.currentThread().isInterrupted) {
            try {
                buffer.clear()
                val read = inputStream.read(buffer.array())
                if (read <= 0) continue

                buffer.limit(read)

                val version = (buffer.get(0).toInt() ushr 4) and 0x0F
                if (version != 4) continue 

                val ihl = (buffer.get(0).toInt() and 0x0F) * 4
                
                if (read < ihl + 8) continue

                val protocol = buffer.get(9).toInt()
                if (protocol != 17) continue 

                buffer.position(ihl)
                val udpSrcPort = buffer.short.toInt() and 0xFFFF
                val udpDstPort = buffer.short.toInt() and 0xFFFF
                val udpLength = buffer.short.toInt() and 0xFFFF

                if (udpDstPort != 53) continue 

                if (udpLength < 8 || read < ihl + udpLength) {
                    continue
                }

                val dnsQueryBytes = ByteArray(udpLength - 8)
                buffer.position(ihl + 8)
                buffer.get(dnsQueryBytes)

                val headerCopy = buffer.array().copyOfRange(0, ihl + 8)

                threadPool.execute {
                    try {
                        val responseBytes = when {
                            !dohUrl.isNullOrEmpty() && !hostName.isNullOrEmpty() -> forwardToDoh(dnsQueryBytes, dohUrl, resolvedIp, hostName)
                            !dotHost.isNullOrEmpty() -> forwardToDot(dnsQueryBytes, dotHost, resolvedIp)
                            else -> forwardToUdp(dnsQueryBytes, primaryDns)
                        }

                        if (responseBytes != null) {
                            val responsePacket = buildResponsePacket(headerCopy, ihl, responseBytes)
                            synchronized(outputStream) {
                                outputStream.write(responsePacket)
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("DnsVpn", "DNS forward failed: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                break
            }
        }
        threadPool.shutdown()
    }

    private fun forwardToDoh(query: ByteArray, urlStr: String, resolvedIp: String?, host: String): ByteArray? {
        try {
            val ipAddress = StaticHosts[host]?.firstOrNull() ?: resolvedIp

            val finalUrlStr = if (!ipAddress.isNullOrEmpty()) {
                urlStr.replace(host, ipAddress)
            } else {
                urlStr
            }

            val url = URL(finalUrlStr)
            val conn = url.openConnection() as HttpsURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/dns-message")
            conn.setRequestProperty("Accept", "application/dns-message")
            conn.connectTimeout = 1500
            conn.readTimeout = 1500
            conn.doOutput = true

            if (!ipAddress.isNullOrEmpty()) {
                conn.setRequestProperty("Host", host)
                conn.setHostnameVerifier { _, session ->
                    HttpsURLConnection.getDefaultHostnameVerifier().verify(host, session)
                }
            }

            conn.getOutputStream().use { os ->
                os.write(query)
            }

            if (conn.responseCode == 200) {
                return conn.inputStream.use { it.readBytes() }
            }
        } catch (e: Exception) {
            Log.e("DnsVpn", "DoH resolution failed: ${e.message}")
        }
        return null
    }

    private fun getOrConnectDotSocket(host: String, resolvedIp: String?): javax.net.ssl.SSLSocket? {
        synchronized(dotLock) {
            if (dotSocket != null && !dotSocket!!.isClosed && dotSocket!!.isConnected) {
                return dotSocket
            }
            closeDotSocket()
            try {
                val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
                val targetHost = resolvedIp ?: host
                val rawSocket = java.net.Socket()
                
                // Establish connection
                rawSocket.connect(java.net.InetSocketAddress(targetHost, 853), 1500)
                
                val sslSocket = factory.createSocket(rawSocket, host, 853, true) as javax.net.ssl.SSLSocket
                sslSocket.soTimeout = 2000
                sslSocket.tcpNoDelay = true

                val sslParams = sslSocket.sslParameters
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                    sslParams.serverNames = listOf(javax.net.ssl.SNIHostName(host))
                }
                
                sslParams.endpointIdentificationAlgorithm = "HTTPS"
                sslSocket.sslParameters = sslParams

                sslSocket.startHandshake()
                dotSocket = sslSocket
                return sslSocket
            } catch (e: Exception) {
                Log.e("DnsVpn", "Failed to connect to DoT resolver: ${e.message}")
                closeDotSocket()
                return null
            }
        }
    }

    private fun closeDotSocket() {
        synchronized(dotLock) {
            try {
                dotSocket?.close()
            } catch (e: Exception) {
                // Ignored
            }
            dotSocket = null
        }
    }

    private fun forwardToDot(query: ByteArray, host: String, resolvedIp: String?): ByteArray? {
        synchronized(dotLock) {
            try {
                val socket = getOrConnectDotSocket(host, resolvedIp) ?: return null
                val os = socket.getOutputStream()
                val inputStream = socket.getInputStream()

                // Write 2-byte prefix length + payload
                val lenBuf = ByteArray(2)
                lenBuf[0] = ((query.size ushr 8) and 0xFF).toByte()
                lenBuf[1] = (query.size and 0xFF).toByte()

                os.write(lenBuf)
                os.write(query)
                os.flush()

                // Read 2-byte prefix response length
                val respLenBuf = ByteArray(2)
                var readBytes = 0
                while (readBytes < 2) {
                    val r = inputStream.read(respLenBuf, readBytes, 2 - readBytes)
                    if (r <= 0) {
                        closeDotSocket()
                        return null
                    }
                    readBytes += r
                }

                val len = ((respLenBuf[0].toInt() and 0xFF) shl 8) or (respLenBuf[1].toInt() and 0xFF)
                if (len <= 0 || len > 65535) {
                    closeDotSocket()
                    return null
                }

                // Read exactly `len` bytes for payload
                val respBuf = ByteArray(len)
                var totalRead = 0
                while (totalRead < len) {
                    val r = inputStream.read(respBuf, totalRead, len - totalRead)
                    if (r <= 0) {
                        closeDotSocket()
                        return null
                    }
                    totalRead += r
                }
                return respBuf
            } catch (e: Exception) {
                Log.e("DnsVpn", "DoT resolution failed: ${e.message}")
                closeDotSocket()
                return null
            }
        }
    }

    private fun forwardToUdp(query: ByteArray, dnsIp: String): ByteArray? {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            socket.soTimeout = 1500
            val targetAddress = InetAddress.getByName(dnsIp)
            val packet = DatagramPacket(query, query.size, targetAddress, 53)
            socket.send(packet)

            val rxBuf = ByteArray(4096)
            val rxPacket = DatagramPacket(rxBuf, rxBuf.size)
            socket.receive(rxPacket)

            val response = ByteArray(rxPacket.length)
            System.arraycopy(rxBuf, 0, response, 0, rxPacket.length)
            return response
        } catch (e: Exception) {
            Log.e("DnsVpn", "UDP resolution failed: ${e.message}")
        } finally {
            socket?.close()
        }
        return null
    }

    private fun buildResponsePacket(requestIpHeader: ByteArray, ihl: Int, dnsResponse: ByteArray): ByteArray {
        val ipLength = 20 + 8 + dnsResponse.size
        val packet = ByteArray(ipLength)

        val srcIp = requestIpHeader.copyOfRange(12, 16)
        val dstIp = requestIpHeader.copyOfRange(16, 20)

        packet[0] = 0x45
        packet[1] = 0x00
        packet[2] = ((ipLength ushr 8) and 0xFF).toByte()
        packet[3] = (ipLength and 0xFF).toByte()
        packet[4] = 0x00
        packet[5] = 0x01
        packet[6] = 0x00
        packet[7] = 0x00
        packet[8] = 64
        packet[9] = 17 
        packet[10] = 0x00 
        packet[11] = 0x00
        System.arraycopy(dstIp, 0, packet, 12, 4) 
        System.arraycopy(srcIp, 0, packet, 16, 4)  

        val ipChecksum = calculateChecksum(packet, 0, 20)
        packet[10] = ((ipChecksum ushr 8) and 0xFF).toByte()
        packet[11] = (ipChecksum and 0xFF).toByte()

        val requestUdpHeader = requestIpHeader.copyOfRange(ihl, ihl + 8)
        val srcPort = requestUdpHeader.copyOfRange(0, 2)
        val dstPort = requestUdpHeader.copyOfRange(2, 4)

        System.arraycopy(dstPort, 0, packet, 20, 2) 
        System.arraycopy(srcPort, 0, packet, 22, 2) 

        val udpLength = 8 + dnsResponse.size
        packet[24] = ((udpLength ushr 8) and 0xFF).toByte()
        packet[25] = (udpLength and 0xFF).toByte()
        packet[26] = 0x00 
        packet[27] = 0x00

        System.arraycopy(dnsResponse, 0, packet, 28, dnsResponse.size)

        return packet
    }

    private fun calculateChecksum(buf: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        var len = length
        while (len > 1) {
            sum += (((buf[i].toInt() and 0xFF) shl 8) or (buf[i + 1].toInt() and 0xFF))
            i += 2
            len -= 2
        }
        if (len > 0) {
            sum += ((buf[i].toInt() and 0xFF) shl 8)
        }
        while ((sum ushr 16) > 0) {
            sum = (sum and 0xFFFF) + (sum ushr 16)
        }
        return (sum.inv()) and 0xFFFF
    }

    private fun stopVpn() {
        isRunning = false 
        vpnThread?.interrupt()
        vpnThread = null
        closeDotSocket()
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            // Handled
        }
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}