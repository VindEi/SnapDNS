using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text;

namespace SnapDns.Service.Services;

public partial class DnsProxyService(ILogger<DnsProxyService> logger) : IDisposable
{
    private UdpClient? _udpListener;
    private static volatile IPAddress[] _bootstrapIps = [];

    private static readonly SocketsHttpHandler Handler = new()
    {
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        ConnectCallback = async (context, cancellationToken) =>
        {
            var host = context.DnsEndPoint.Host;
            var port = context.DnsEndPoint.Port;

            IPAddress[] ips = await ResolveHostAsync(host, cancellationToken);

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

    public Task<bool> StartAsync(string dohUrl, string dotHostname, string primaryDns = "", string secondaryDns = "")
    {
        Stop();
        ActiveDohUrl = dohUrl;
        ActiveDotHostname = dotHostname;

        var bootstrapList = new List<IPAddress>();
        if (IPAddress.TryParse(primaryDns, out var pIp) && !IPAddress.IsLoopback(pIp) && pIp.AddressFamily == AddressFamily.InterNetwork)
            bootstrapList.Add(pIp);
        if (IPAddress.TryParse(secondaryDns, out var sIp) && !IPAddress.IsLoopback(sIp) && sIp.AddressFamily == AddressFamily.InterNetwork)
            bootstrapList.Add(sIp);
        _bootstrapIps = [.. bootstrapList];

        _cts = new CancellationTokenSource();
        try
        {
            _udpListener = CreateUdpListener();
            _ = Task.Run(() => ListenLoop(dohUrl, dotHostname, _cts.Token));
            return Task.FromResult(true);
        }
        catch (Exception ex)
        {
            logger.LogError("Proxy bind failed: {Msg}", ex.Message);
            return Task.FromResult(false);
        }
    }

    private const int SioUdpConnReset = -1744830452;

    private static void DisableWindowsConnReset(Socket socket)
    {
        if (OperatingSystem.IsWindows())
        {
            try { socket.IOControl(SioUdpConnReset, [0], null); } catch { }
        }
    }

    private UdpClient CreateUdpListener()
    {
        var listener = new UdpClient(new IPEndPoint(IPAddress.Loopback, 53));
        DisableWindowsConnReset(listener.Client);
        return listener;
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
                break;
            }
            catch (SocketException ex) when (ex.SocketErrorCode == SocketError.ConnectionReset)
            {
                continue;
            }
            catch (Exception ex)
            {
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
                        _udpListener = CreateUdpListener();
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
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(2500);

        try
        {
            await _dotStreamSemaphore.WaitAsync(timeoutCts.Token);
        }
        catch (OperationCanceledException)
        {
            return null;
        }

        try
        {
            var stream = await GetDotStream(host, timeoutCts.Token);
            if (stream == null) return null;

            byte[] tcpQuery = new byte[query.Length + 2];
            BinaryPrimitives.WriteUInt16BigEndian(tcpQuery.AsSpan(0, 2), (ushort)query.Length);
            query.CopyTo(tcpQuery, 2);

            await stream.WriteAsync(tcpQuery, timeoutCts.Token);

            byte[] lenBuf = new byte[2];
            await stream.ReadExactlyAsync(lenBuf, timeoutCts.Token);
            byte[] resp = new byte[BinaryPrimitives.ReadUInt16BigEndian(lenBuf)];
            await stream.ReadExactlyAsync(resp, timeoutCts.Token);
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
            _dotClient.ReceiveTimeout = 2000;
            _dotClient.SendTimeout = 2000;

            IPAddress[] ips = await ResolveHostAsync(host, ct);

            await _dotClient.ConnectAsync(ips, 853, ct);
            _dotStream = new SslStream(_dotClient.GetStream(), false);
            await _dotStream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions { TargetHost = host }, ct);
            return _dotStream;
        }
        catch { return null; }
        finally { _dotSemaphore.Release(); }
    }

    private static async Task<IPAddress[]> ResolveHostAsync(string host, CancellationToken ct)
    {
        if (host == "127.0.0.1" || host == "localhost") return [IPAddress.Loopback];
        if (IPAddress.TryParse(host, out var directIp)) return [directIp];

        var bootstrap = _bootstrapIps;
        if (bootstrap.Length > 0)
        {
            var resolved = await ResolveHostViaUdpBootstrap(host, bootstrap, ct);
            if (resolved.Length > 0) return resolved;
            return bootstrap;
        }

        try
        {
            return await Dns.GetHostAddressesAsync(host, ct);
        }
        catch
        {
            return [];
        }
    }

    internal static async Task<IPAddress[]> ResolveHostViaUdpBootstrap(string host, IPAddress[] bootstrapServers, CancellationToken ct)
    {
        if (bootstrapServers.Length == 0) return [];
        byte[] query = BuildDnsQuery(host);

        foreach (var server in bootstrapServers)
        {
            try
            {
                using var udp = new UdpClient();
                udp.Client.SendTimeout = 1500;
                udp.Client.ReceiveTimeout = 1500;

                DisableWindowsConnReset(udp.Client);

                await udp.SendAsync(query, query.Length, new IPEndPoint(server, 53));
                var result = await udp.ReceiveAsync(ct);
                var resolved = ParseDnsResponse(result.Buffer);
                if (resolved.Length > 0) return resolved;
            }
            catch
            {
                // Fall through to next bootstrap server
            }
        }
        return [];
    }

    public static byte[] BuildDnsQuery(string domain)
    {
        var parts = domain.Split('.');
        var query = new List<byte> { 0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
        foreach (var part in parts)
        {
            byte len = (byte)part.Length;
            query.Add(len);
            query.AddRange(Encoding.ASCII.GetBytes(part));
        }
        query.Add(0x00);
        query.AddRange([0x00, 0x01, 0x00, 0x01]);
        return [.. query];
    }

    public static IPAddress[] ParseDnsResponse(byte[] buffer)
    {
        try
        {
            if (buffer.Length < 12) return [];
            int questions = BinaryPrimitives.ReadUInt16BigEndian(buffer.AsSpan(4, 2));
            int answers = BinaryPrimitives.ReadUInt16BigEndian(buffer.AsSpan(6, 2));

            int pos = 12;
            for (int i = 0; i < questions; i++)
            {
                pos = SkipName(buffer, pos);
                pos += 4;
            }

            var ips = new List<IPAddress>();
            for (int i = 0; i < answers; i++)
            {
                pos = SkipName(buffer, pos);
                if (pos + 10 > buffer.Length) break;

                ushort type = BinaryPrimitives.ReadUInt16BigEndian(buffer.AsSpan(pos, 2));
                ushort dataLen = BinaryPrimitives.ReadUInt16BigEndian(buffer.AsSpan(pos + 8, 2));
                pos += 10;

                if (type == 1 && dataLen == 4)
                {
                    if (pos + 4 <= buffer.Length)
                    {
                        ips.Add(new IPAddress(buffer.AsSpan(pos, 4).ToArray()));
                    }
                }
                else if (type == 28 && dataLen == 16)
                {
                    if (pos + 16 <= buffer.Length)
                    {
                        ips.Add(new IPAddress(buffer.AsSpan(pos, 16).ToArray()));
                    }
                }
                pos += dataLen;
            }
            return [.. ips];
        }
        catch { return []; }
    }

    private static int SkipName(byte[] buffer, int offset)
    {
        while (offset < buffer.Length)
        {
            int len = buffer[offset];
            if ((len & 0xC0) == 0xC0) return offset + 2;
            if (len == 0) return offset + 1;
            offset += len + 1;
        }
        return offset;
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
        _bootstrapIps = [];
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
