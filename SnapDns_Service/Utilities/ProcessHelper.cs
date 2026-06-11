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

            // FIXED: Added null check to prevent dereference warning
            if (p == null)
            {
                logger?.LogWarning("OS failed to start process: {Cmd}", cmd);
                return false;
            }

            p.WaitForExit();

            if (p.ExitCode != 0 && logger != null)
            {
                string error = p.StandardError.ReadToEnd();
                logger.LogWarning("CLI Error: {Cmd} Code {Code}. Msg: {Msg}", cmd, p.ExitCode, error);
            }

            return p.ExitCode == 0;
        }
        catch (Exception ex)
        {
            logger?.LogWarning("CLI Execution failed: {Cmd}. Error: {Msg}", cmd, ex.Message);
            return false;
        }
    }
}