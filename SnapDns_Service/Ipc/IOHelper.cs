using System.Text;

namespace SnapDns.Service.Ipc;

public static class IOHelper
{
    public static async Task WriteStringAsync(Stream stream, string value, CancellationToken ct)
    {
        var data = Encoding.UTF8.GetBytes(value);
        var lengthBytes = BitConverter.GetBytes(data.Length); // Little Endian
        await stream.WriteAsync(lengthBytes.AsMemory(0, 4), ct);
        await stream.WriteAsync(data, ct);
        await stream.FlushAsync(ct);
    }

    public static async Task<string> ReadStringAsync(Stream stream, CancellationToken ct)
    {
        var lengthBytes = new byte[4];
        int read = await stream.ReadAsync(lengthBytes.AsMemory(0, 4), ct);
        if (read < 4) return string.Empty;

        int length = BitConverter.ToInt32(lengthBytes, 0);
        if (length <= 0 || length > 1024 * 512) return string.Empty;

        var buffer = new byte[length];
        int totalRead = 0;
        while (totalRead < length)
        {
            int r = await stream.ReadAsync(buffer.AsMemory(totalRead, length - totalRead), ct);
            if (r == 0) break;
            totalRead += r;
        }
        return Encoding.UTF8.GetString(buffer);
    }
}