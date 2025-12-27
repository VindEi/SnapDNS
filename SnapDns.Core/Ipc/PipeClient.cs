using SnapDns.Core.Models;
using System;
using System.IO;
using System.IO.Pipes;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace SnapDns.Core.Ipc;

/// <summary>
/// Handles client-side communication with the SnapDns background service over a secure Named Pipe.
/// This is a cross-platform IPC implementation.
/// </summary>
public class PipeClient
{
    // 5 seconds timeout for connection and I/O
    private const int TimeoutMs = 5000;

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        // Use camelCase to match the service's serialization policy for requests/responses
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    /// <summary>
    /// Sends a PipeRequest to the service and waits for a PipeResponse.
    /// </summary>
    /// <param name="request">The request DTO containing the command and data.</param>
    /// <param name="cancellationToken">Cancellation token for pipe operations.</param>
    /// <returns>The response DTO from the service.</returns>
    public async Task<PipeResponse> SendCommandAsync(PipeRequest request, CancellationToken cancellationToken = default)
    {
        try
        {
            // 1. Establish the connection
            using var pipeClient = new NamedPipeClientStream(
                serverName: ".",                  // Local machine
                pipeName: PipeConstants.PipeName, // Defined in SnapDns.Core.Ipc
                direction: PipeDirection.InOut,
                options: PipeOptions.Asynchronous
            );

            // Wait up to 5 seconds for the service to be available and connected.
            await pipeClient.ConnectAsync(TimeoutMs, cancellationToken);

            if (!pipeClient.IsConnected)
            {
                return new PipeResponse
                {
                    Success = false,
                    Message = $"Failed to connect to SnapDns Service pipe: '{PipeConstants.PipeName}'. The service may not be running or accessible."
                };
            }

            // 2. Send the Request
            var jsonRequest = JsonSerializer.Serialize(request, _jsonOptions);
            await IOHelper.WriteStringAsync(pipeClient, jsonRequest, cancellationToken);

            // 3. Receive the Response
            var jsonResponse = await IOHelper.ReadStringAsync(pipeClient, cancellationToken);

            if (string.IsNullOrWhiteSpace(jsonResponse))
            {
                return new PipeResponse { Success = false, Message = "Service returned an empty or invalid response." };
            }

            var response = JsonSerializer.Deserialize<PipeResponse>(jsonResponse, _jsonOptions);
            return response ?? new PipeResponse { Success = false, Message = "Failed to deserialize service response." };
        }
        catch (TimeoutException)
        {
            return new PipeResponse { Success = false, Message = "Connection timeout. The SnapDns Service may be stopped or too slow to respond." };
        }
        catch (OperationCanceledException)
        {
            return new PipeResponse { Success = false, Message = "The IPC operation was cancelled." };
        }
        catch (EndOfStreamException ex)
        {
            return new PipeResponse { Success = false, Message = $"IPC data error: Incomplete response received. {ex.Message}" };
        }
        catch (Exception ex)
        {
            return new PipeResponse { Success = false, Message = $"IPC connection error: {ex.Message}" };
        }
    }
}