using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;

namespace SnapDns.Service.Services;

public partial class DnsProxyService(ILogger<DnsProxyService> logger) : IDisposable
{
    private UdpClient? _udpListener;
    
    private static readonly Dictionary<string, IPAddress[]> StaticHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        { "cloudflare-dns.com", [IPAddress.Parse("1.1.1.1"), IPAddress.Parse("1.0.0.1")] },
        { "one.one.one.one", [IPAddress.Parse("1.1.1.1"), IPAddress.Parse("1.0.0.1")] },
        { "dns.google", [IPAddress.Parse("8.8.8.8"), IPAddress.Parse("8.8.4.4")] },
        { "dns.quad9.net", [IPAddress.Parse("9.9.9.9"), IPAddress.Parse("149.112.112.112")] },
        { "dns.adguard-dns.com", [IPAddress.Parse("94.140.14.14"), IPAddress.Parse("94.140.15.15")] }
    };

    private static readonly SocketsHttpHandler Handler = new() 
    { 
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        ConnectCallback = async (context, cancellationToken) =>
        {
            var host = context.DnsEndPoint.Host;
            var port = context.DnsEndPoint.Port;
            
            IPAddress[] ips;
            if (host == "127.0.0.1" || host == "localhost")
            {
                ips = [IPAddress.Loopback];
            }
            else if (StaticHosts.TryGetValue(host, out var cachedIps))
            {
                ips = cachedIps;
            }
            else
            {
                ips = await Dns.GetHostAddressesAsync(host, cancellationToken);
            }
            
            var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
            try
            {
                await socket.ConnectAsync(ips, port, cancellationToken);
                return new NetworkStream(socket, true);
            }
            catch
            {
                socket.Dispose();
                throw;
            }
        }
    };
    
    private static readonly HttpClient _httpClient = new(Handler);

    private CancellationTokenSource? _cts;
    private readonly SemaphoreSlim _throttle = new(100);

    private TcpClient? _dotClient;
    private SslStream? _dotStream;
    private readonly SemaphoreSlim _dotSemaphore = new(1, 1);
    private readonly SemaphoreSlim _dotStreamSemaphore = new(1, 1);

    public string? ActiveDohUrl { get; private set; }
    public string? ActiveDotHostname { get; private set; }

    public Task<bool> StartAsync(string dohUrl, string dotHostname)
    {
        Stop();
        ActiveDohUrl = dohUrl;
        ActiveDotHostname = dotHostname;

        _cts = new CancellationTokenSource();
        try
        {
            _udpListener = new UdpClient(new IPEndPoint(IPAddress.Loopback, 53));
            _ = Task.Run(() => ListenLoop(dohUrl, dotHostname, _cts.Token));
            return Task.FromResult(true);
        }
        catch (Exception ex) 
        { 
            logger.LogError("Proxy bind failed: {Msg}", ex.Message); 
            return Task.FromResult(false);
        }
    }

    private async Task ListenLoop(string doh, string dot, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                if (_udpListener == null) break;
                var result = await _udpListener.ReceiveAsync(ct);
                _ = HandleQuery(result, doh, dot, ct);
            }
            catch (OperationCanceledException)
            {
                break; // Intentional service shutdown
            }
            catch (Exception ex)
            {
                // FIX: If the cancellation token was triggered, abort immediately and do not attempt to re-bind the socket.
                // Prevents background proxy leaks when transitioning back to standard IPv4 configs.
                if (ct.IsCancellationRequested)
                {
                    break;
                }

                logger.LogWarning("UDP Listen error: {Msg}. Attempting socket re-bind in 1s...", ex.Message);

                if (_udpListener == null || ex is ObjectDisposedException || ex is SocketException)
                {
                    try
                    {
                        _udpListener?.Dispose();
                        _udpListener = new UdpClient(new IPEndPoint(IPAddress.Loopback, 53));
                    }
                    catch (Exception rebindEx)
                    {
                        logger.LogError("Failed to rebind UDP listener to Port 53: {Msg}", rebindEx.Message);
                    }
                }

                try 
                { 
                    await Task.Delay(1000, ct); 
                } 
                catch 
                { 
                    break; 
                }
            }
        }
    }

    private async Task HandleQuery(UdpReceiveResult request, string doh, string dot, CancellationToken ct)
    {
        try
        {
            if (await _throttle.WaitAsync(2000, ct))
            {
                try
                {
                    byte[]? response = !string.IsNullOrEmpty(doh)
                        ? await ForwardToDoh(request.Buffer, doh, ct)
                        : await ForwardToDot(request.Buffer, dot, ct);

                    if (response != null && _udpListener != null)
                        await _udpListener.SendAsync(response, response.Length, request.RemoteEndPoint);
                }
                finally { _throttle.Release(); }
            }
        }
        catch (Exception ex)
        {
            logger.LogDebug("Query handling failed: {Msg}", ex.Message);
        }
    }

    private static async Task<byte[]?> ForwardToDoh(byte[] query, string url, CancellationToken ct)
    {
        try
        {
            using var content = new ByteArrayContent(query);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/dns-message");
            var resp = await _httpClient.PostAsync(url, content, ct);
            
            if (resp.IsSuccessStatusCode && resp.Content.Headers.ContentType?.MediaType == "application/dns-message")
            {
                return await resp.Content.ReadAsByteArrayAsync(ct);
            }
            return null;
        }
        catch { return null; }
    }

    private async Task<byte[]?> ForwardToDot(byte[] query, string host, CancellationToken ct)
    {
        await _dotStreamSemaphore.WaitAsync(ct);
        try
        {
            var stream = await GetDotStream(host, ct);
            if (stream == null) return null;

            byte[] tcpQuery = new byte[query.Length + 2];
            BinaryPrimitives.WriteUInt16BigEndian(tcpQuery.AsSpan(0, 2), (ushort)query.Length);
            query.CopyTo(tcpQuery, 2);

            await stream.WriteAsync(tcpQuery, ct);

            byte[] lenBuf = new byte[2];
            await stream.ReadExactlyAsync(lenBuf, ct);
            byte[] resp = new byte[BinaryPrimitives.ReadUInt16BigEndian(lenBuf)];
            await stream.ReadExactlyAsync(resp, ct);
            return resp;
        }
        catch 
        { 
            CloseDot(); 
            return null; 
        }
        finally 
        { 
            _dotStreamSemaphore.Release(); 
        }
    }

    private async Task<SslStream?> GetDotStream(string host, CancellationToken ct)
    {
        if (_dotStream != null && _dotClient?.Connected == true) return _dotStream;

        await _dotSemaphore.WaitAsync(ct);
        try
        {
            if (_dotStream != null && _dotClient?.Connected == true) return _dotStream;
            CloseDot();
            
            _dotClient = new TcpClient();

            IPAddress[] ips;
            if (StaticHosts.TryGetValue(host, out var cachedIps))
            {
                ips = cachedIps;
            }
            else
            {
                ips = await Dns.GetHostAddressesAsync(host, ct);
            }

            await _dotClient.ConnectAsync(ips, 853, ct);
            _dotStream = new SslStream(_dotClient.GetStream(), false);
            await _dotStream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions { TargetHost = host }, ct);
            return _dotStream;
        }
        catch { return null; }
        finally { _dotSemaphore.Release(); }
    }

    private void CloseDot() { _dotStream?.Dispose(); _dotClient?.Dispose(); _dotStream = null; _dotClient = null; }
    
    public void Stop() 
    { 
        _cts?.Cancel(); 
        _udpListener?.Dispose(); 
        _udpListener = null; 
        CloseDot(); 
        ActiveDohUrl = null; 
        ActiveDotHostname = null; 
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
        _dotSemaphore.Dispose();
        _dotStreamSemaphore.Dispose();
        _throttle.Dispose();
        GC.SuppressFinalize(this);
    }
}