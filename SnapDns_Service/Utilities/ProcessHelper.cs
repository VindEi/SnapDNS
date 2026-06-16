using System.Diagnostics;

namespace SnapDns.Service.Utilities;

public static class ProcessHelper
{
    public static bool Run(string cmd, IEnumerable<string> args, ILogger? logger = null)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = cmd,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardError = true
            };

            foreach (var arg in args) psi.ArgumentList.Add(arg);

            using var p = Process.Start(psi);

            if (p == null)
            {
                logger?.LogWarning("OS failed to start process: {Cmd}", cmd);
                return false;
            }

            // Read the standard error stream asynchronously in the background to prevent deadlocks
            var errorReaderTask = p.StandardError.ReadToEndAsync();

            if (p.WaitForExit(5000))
            {
                // FIX: Always observe and retrieve the task result after process termination.
                // This ensures the asynchronous task completes, releasing the underlying Win32/Unix file handle immediately.
                string error = errorReaderTask.GetAwaiter().GetResult();

                if (p.ExitCode != 0 && logger != null)
                {
                    logger.LogWarning("CLI Error: {Cmd} Code {Code}. Msg: {Msg}", cmd, p.ExitCode, error);
                }
                return p.ExitCode == 0;
            }
            else
            {
                p.Kill(); // Force-terminate hanging processes
                logger?.LogWarning("Process execution timed out and was forcibly terminated: {Cmd}", cmd);
                return false;
            }
        }
        catch (Exception ex)
        {
            logger?.LogWarning("CLI Execution failed: {Cmd}. Error: {Msg}", cmd, ex.Message);
            return false;
        }
    }
}