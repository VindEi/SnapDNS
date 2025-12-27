using Microsoft.Extensions.Logging;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace SnapDns.Service.Services
{
    /// <summary>
    /// A lightweight local DNS server (UDP 53) that forwards queries to a DoH provider via HTTPS.
    /// Used to support Custom DoH on Windows 10/11 and provide a consistent experience across platforms.
    /// </summary>
    public class DnsProxyService(ILogger<DnsProxyService> logger) : IDisposable
    {
        private HttpClient? _httpClient;
        private UdpClient? _udpListener;
        private CancellationTokenSource? _cts;
        private string _currentDohUrl = string.Empty;
        private bool _isRunning = false;

        private const string LocalBindAddress = "127.0.0.1";
        private const int LocalBindPort = 53;

        /// <summary>
        /// Starts the local UDP listener on 127.0.0.1:53 and configures the upstream DoH provider.
        /// </summary>
        /// <param name="dohUrl">The https URL of the DoH provider.</param>
        public async Task StartAsync(string dohUrl)
        {
            if (_isRunning && _currentDohUrl == dohUrl) return;
            Stop();

            logger.LogInformation("Starting DNS Proxy targeting: {Url}", dohUrl);
            _currentDohUrl = dohUrl;
            _cts = new CancellationTokenSource();

            try
            {
                // 1. Bootstrap: Resolve DoH hostname to IP using system DNS before we override it.
                var dohUri = new Uri(dohUrl);
                IPAddress? targetIp = null;

                if (dohUri.HostNameType == UriHostNameType.Dns)
                {
                    try
                    {
                        var ips = await Dns.GetHostAddressesAsync(dohUri.Host);
                        targetIp = ips.FirstOrDefault(ip => ip.AddressFamily == AddressFamily.InterNetwork);
                        logger.LogInformation("Bootstrapped DoH Host '{Host}' to IP '{Ip}'", dohUri.Host, targetIp);
                    }
                    catch (Exception ex)
                    {
                        logger.LogError("Failed to bootstrap DoH hostname: {Message}", ex.Message);
                    }
                }

                // 2. Configure HttpClient
                var handler = new SocketsHttpHandler();

                if (targetIp != null)
                {
                    // Force connection to the resolved IP to avoid loops
                    handler.ConnectCallback = async (context, token) =>
                    {
                        var socket = new Socket(SocketType.Stream, ProtocolType.Tcp);
                        await socket.ConnectAsync(targetIp, dohUri.Port, token);
                        return new NetworkStream(socket, ownsSocket: true);
                    };
                }

                _httpClient = new HttpClient(handler);
                _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("SnapDns-Proxy/1.0");

                // 3. Start Listener
                _udpListener = new UdpClient(new IPEndPoint(IPAddress.Parse(LocalBindAddress), LocalBindPort));

                // WINDOWS FIX: Disable SIO_UDP_CONNRESET to prevent crash on ICMP errors
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    try
                    {
                        const int SIO_UDP_CONNRESET = -1744830452;
                        _udpListener.Client.IOControl((IOControlCode)SIO_UDP_CONNRESET, [0], null);
                    }
                    catch { /* Ignore if IOControl not supported */ }
                }

                _isRunning = true;
                _ = Task.Run(() => ListenLoopAsync(_cts.Token), _cts.Token);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to bind DNS Proxy to {Addr}:{Port}.", LocalBindAddress, LocalBindPort);
                _isRunning = false;
            }
        }

        /// <summary>
        /// Stops the proxy and releases resources.
        /// </summary>
        public void Stop()
        {
            if (!_isRunning) return;

            logger.LogInformation("Stopping DNS Proxy.");
            _cts?.Cancel();

            _udpListener?.Close();
            _udpListener?.Dispose();
            _udpListener = null;

            _httpClient?.Dispose();
            _httpClient = null;

            _isRunning = false;
        }

        private async Task ListenLoopAsync(CancellationToken token)
        {
            while (!token.IsCancellationRequested && _udpListener != null)
            {
                try
                {
                    var result = await _udpListener.ReceiveAsync(token);

                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var responseBytes = await ForwardToDohAsync(result.Buffer, _currentDohUrl, token);
                            if (responseBytes != null && _udpListener != null)
                            {
                                await _udpListener.SendAsync(responseBytes, responseBytes.Length, result.RemoteEndPoint);
                            }
                        }
                        catch { /* Ignore forwarding errors */ }
                    }, token);
                }
                catch (ObjectDisposedException) { break; }
                catch (SocketException ex) when (ex.SocketErrorCode == SocketError.ConnectionReset)
                {
                    continue; // Ignore Windows 10054 error
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    logger.LogError(ex, "DNS Proxy Loop Error");
                    await Task.Delay(100, token);
                }
            }
        }

        private async Task<byte[]?> ForwardToDohAsync(byte[] queryBytes, string url, CancellationToken token)
        {
            if (_httpClient == null) return null;

            using var content = new ByteArrayContent(queryBytes);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/dns-message");

            using var response = await _httpClient.PostAsync(url, content, token);

            if (response.IsSuccessStatusCode)
            {
                return await response.Content.ReadAsByteArrayAsync(token);
            }

            return null;
        }

        public void Dispose()
        {
            Stop();
            _cts?.Dispose();
            GC.SuppressFinalize(this);
        }
    }
}