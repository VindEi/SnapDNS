using SnapDns.Core.Models;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace SnapDns.Core.Ipc;

// These DTOs define the exact structure of the JSON sent over the Named Pipe.

/// <summary>
/// Defines the command type sent from the client to the service.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum PipeCommandType
{
    ApplyDns,
    ResetDhcp,
    GetConfiguration,
    GetAdapters,
    GetPreferredAdapter,
    FlushDns
}

/// <summary>
/// Request object sent from the client over the Named Pipe.
/// </summary>
public class PipeRequest
{
    public PipeCommandType Command { get; set; }
    public string AdapterName { get; set; } = string.Empty;

    /// <summary>
    /// Contains the DNS servers to be applied when Command is ApplyDns.
    /// </summary>
    public DnsConfiguration? Configuration { get; set; }
}

/// <summary>
/// Response object sent from the service back to the client.
/// </summary>
public class PipeResponse
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Contains the current DNS configuration if Command was GetConfiguration.
    /// </summary>
    public DnsConfiguration? Configuration { get; set; }

    /// <summary>
    /// Contains a list of all IP-enabled network adapter names/IDs.
    /// </summary>
    public List<string>? Adapters { get; set; }

    /// <summary>
    /// Contains the name of the preferred (active) adapter if requested.
    /// </summary>
    public string? PreferredAdapterName { get; set; }
}