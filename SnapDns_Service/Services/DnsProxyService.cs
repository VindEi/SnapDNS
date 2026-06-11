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
    private static readonly SocketsHttpHandler Handler = new() { PooledConnectionLifetime = TimeSpan.FromMinutes(5) };
    private static readonly HttpClient _httpClient = new(Handler);

    private CancellationTokenSource? _cts;
    private readonly SemaphoreSlim _throttle = new(100);

    private TcpClient? _dotClient;
    private SslStream? _dotStream;
    private readonly SemaphoreSlim _dotSemaphore = new(1, 1);

    public Task StartAsync(string dohUrl, string dotHostname)
    {
        Stop();
        _cts = new CancellationTokenSource();
        try
        {
            _udpListener = new UdpClient(new IPEndPoint(IPAddress.Loopback, 53));
            _ = Task.Run(() => ListenLoop(dohUrl, dotHostname, _cts.Token));
        }
        catch (Exception ex) { logger.LogError("Proxy bind failed: {Msg}", ex.Message); }
        return Task.CompletedTask;
    }

    private async Task ListenLoop(string doh, string dot, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _udpListener != null)
        {
            try
            {
                var result = await _udpListener.ReceiveAsync(ct);
                _ = HandleQuery(result, doh, dot, ct);
            }
            catch { break; }
        }
    }

    private async Task HandleQuery(UdpReceiveResult request, string doh, string dot, CancellationToken ct)
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

    private static async Task<byte[]?> ForwardToDoh(byte[] query, string url, CancellationToken ct)
    {
        try
        {
            using var content = new ByteArrayContent(query);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/dns-message");
            var resp = await _httpClient.PostAsync(url, content, ct);
            return resp.IsSuccessStatusCode ? await resp.Content.ReadAsByteArrayAsync(ct) : null;
        }
        catch { return null; }
    }

    private async Task<byte[]?> ForwardToDot(byte[] query, string host, CancellationToken ct)
    {
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
        catch { CloseDot(); return null; }
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
            await _dotClient.ConnectAsync(host, 853, ct);
            _dotStream = new SslStream(_dotClient.GetStream(), false);
            await _dotStream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions { TargetHost = host }, ct);
            return _dotStream;
        }
        catch { return null; }
        finally { _dotSemaphore.Release(); }
    }

    private void CloseDot() { _dotStream?.Dispose(); _dotClient?.Dispose(); _dotStream = null; _dotClient = null; }
    public void Stop() { _cts?.Cancel(); _udpListener?.Dispose(); _udpListener = null; CloseDot(); }

    // FIXED: Added SuppressFinalize to complete the IDisposable pattern
    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
        _dotSemaphore.Dispose();
        _throttle.Dispose();
        GC.SuppressFinalize(this);
    }
}