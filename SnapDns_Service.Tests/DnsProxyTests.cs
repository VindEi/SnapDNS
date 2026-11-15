using System.Buffers.Binary;
using System.Net;
using SnapDns.Service.Services;
using Xunit;

namespace SnapDns_Service.Tests;

public class DnsProxyTests
{
    [Fact]
    public void BuildDnsQuery_ConstructsValidStandardDnsQuery()
    {
        string domain = "example.com";
        byte[] query = DnsProxyService.BuildDnsQuery(domain);

        Assert.NotNull(query);
        Assert.True(query.Length > 12);

        // Transaction ID
        Assert.Equal(0x12, query[0]);
        Assert.Equal(0x34, query[1]);

        // Standard query flags
        Assert.Equal(0x01, query[2]);
        Assert.Equal(0x00, query[3]);

        // Questions count = 1
        ushort questions = BinaryPrimitives.ReadUInt16BigEndian(query.AsSpan(4, 2));
        Assert.Equal(1, questions);

        // Contains "example" and "com" labels
        Assert.Equal(7, query[12]); // Length of "example"
        Assert.Equal(3, query[12 + 1 + 7]); // Length of "com"
    }

    [Fact]
    public void ParseDnsResponse_ParsesIPv4ResponseCorrectly()
    {
        // Synthesize a minimal DNS response containing 1 question and 1 A answer pointing to 93.184.216.34
        var response = new List<byte>
        {
            // Header (12 bytes)
            0x12, 0x34, // ID
            0x81, 0x80, // Standard response flags (No error)
            0x00, 0x01, // Questions: 1
            0x00, 0x01, // Answer RRs: 1
            0x00, 0x00, // Authority RRs: 0
            0x00, 0x00, // Additional RRs: 0

            // Question: example.com, Type A (1), Class IN (1)
            0x07, 0x65, 0x78, 0x61, 0x6d, 0x70, 0x6c, 0x65, // "example"
            0x03, 0x63, 0x6f, 0x6d, // "com"
            0x00, // root
            0x00, 0x01, // Type A
            0x00, 0x01, // Class IN

            // Answer: Pointer to name (0xC00C), Type A (1), Class IN (1), TTL (60), Length (4), IP (93.184.216.34)
            0xC0, 0x0C, // Name pointer
            0x00, 0x01, // Type A
            0x00, 0x01, // Class IN
            0x00, 0x00, 0x00, 0x3C, // TTL: 60s
            0x00, 0x04, // Data Length: 4 bytes
            93, 184, 216, 34 // 93.184.216.34
        };

        IPAddress[] ips = DnsProxyService.ParseDnsResponse(response.ToArray());

        Assert.Single(ips);
        Assert.Equal(IPAddress.Parse("93.184.216.34"), ips[0]);
    }

    [Fact]
    public void ParseDnsResponse_ReturnsEmptyOnTruncatedOrInvalidBuffer()
    {
        byte[] invalidBuffer = [0x00, 0x01, 0x02];
        IPAddress[] ips = DnsProxyService.ParseDnsResponse(invalidBuffer);

        Assert.Empty(ips);
    }
}
