using System.Diagnostics;

namespace SnapDns.Service.Utilities;

public static class ProcessHelper
{
    public static bool Run(string cmd, IEnumerable<string> args, ILogger? logger = null)
    {
        return RunInternal(cmd, args, 10000, logger, out _);
    }

    public static string? RunWithOutput(string cmd, IEnumerable<string> args, int timeoutMs = 10000, ILogger? logger = null)
    {
        bool success = RunInternal(cmd, args, timeoutMs, logger, out string output);
        return success ? output : null;
    }

    private static bool RunInternal(string cmd, IEnumerable<string> args, int timeoutMs, ILogger? logger, out string stdout)
    {
        stdout = string.Empty;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = cmd,
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            foreach (var arg in args) psi.ArgumentList.Add(arg);

            using var p = Process.Start(psi);
            if (p == null)
            {
                logger?.LogWarning("OS failed to start process: {Cmd}", cmd);
                return false;
            }

            var outputTask = p.StandardOutput.ReadToEndAsync();
            var errorTask = p.StandardError.ReadToEndAsync();

            if (p.WaitForExit(timeoutMs))
            {
                stdout = outputTask.GetAwaiter().GetResult();
                string error = errorTask.GetAwaiter().GetResult();

                if (p.ExitCode != 0 && logger != null)
                {
                    logger.LogWarning("CLI Error: {Cmd} Code {Code}. Output: {Out} Msg: {Msg}", cmd, p.ExitCode, stdout, error);
                }
                return p.ExitCode == 0;
            }
            else
            {
                try { p.Kill(); } catch { }
                logger?.LogWarning("Process execution timed out ({Timeout}ms): {Cmd}", timeoutMs, cmd);
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
