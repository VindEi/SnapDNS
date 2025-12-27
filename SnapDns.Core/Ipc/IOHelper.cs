using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace SnapDns.Core.Ipc;

/// <summary>
/// Provides utility methods for reliable string communication over Named Pipes
/// using a length-prefixing protocol (4-byte length prefix + payload).
/// This ensures synchronization between the client and server.
/// </summary>
public static class IOHelper
{
    /// <summary>
    /// Writes a string to the pipe stream, prefixed by its length (4 bytes).
    /// </summary>
    public static async Task WriteStringAsync(PipeStream stream, string value, CancellationToken cancellationToken = default)
    {
        var data = Encoding.UTF8.GetBytes(value);
        var lengthBytes = BitConverter.GetBytes(data.Length);

        // 1. Write the length of the message (4 bytes)
        await stream.WriteAsync(lengthBytes.AsMemory(0, 4), cancellationToken);

        // 2. Write the message payload
        await stream.WriteAsync(data, cancellationToken);
    }

    /// <summary>
    /// Reads a string from the pipe stream based on a 4-byte length prefix.
    /// </summary>
    public static async Task<string> ReadStringAsync(PipeStream stream, CancellationToken cancellationToken = default)
    {
        // 1. Read the 4-byte length prefix
        var lengthBytes = new byte[4];

        if (await stream.ReadAsync(lengthBytes.AsMemory(0, 4), cancellationToken) == 0)
        {
            return string.Empty;
        }

        var length = BitConverter.ToInt32(lengthBytes, 0);

        if (length <= 0)
        {
            return string.Empty;
        }

        // 2. Read the payload based on the determined length
        var buffer = new byte[length];
        var bytesRead = 0;

        while (bytesRead < length)
        {
            var remaining = length - bytesRead;
            var readCount = await stream.ReadAsync(buffer.AsMemory(bytesRead, remaining), cancellationToken);

            if (readCount == 0)
            {
                throw new EndOfStreamException($"Pipe closed unexpectedly while reading {length} bytes. Only {bytesRead} received.");
            }
            bytesRead += readCount;
        }

        return Encoding.UTF8.GetString(buffer, 0, length);
    }
}