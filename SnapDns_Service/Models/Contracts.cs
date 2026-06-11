using System.Text.Json.Serialization;

namespace SnapDns.Service.Models;

public class DnsConfiguration
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string PrimaryDns { get; set; } = string.Empty;
    public string SecondaryDns { get; set; } = string.Empty;
    public string Ipv6Primary { get; set; } = string.Empty;
    public string Ipv6Secondary { get; set; } = string.Empty;
    public string DohUrl { get; set; } = string.Empty;
    public string DotHostname { get; set; } = string.Empty;
}

public enum PipeCommandType
{
    applyDns,
    resetDhcp,
    getConfiguration,
    getAdapters,
    getPreferredAdapter,
    flushDns,
    getSyncState // MATCHED
}

public class PipeRequest
{
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public PipeCommandType Command { get; set; }
    public string AdapterName { get; set; } = string.Empty;
    public DnsConfiguration? Configuration { get; set; }
}

public class PipeResponse
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public DnsConfiguration? Configuration { get; set; }
    public List<string>? Adapters { get; set; }
    public string? PreferredAdapterName { get; set; }
}