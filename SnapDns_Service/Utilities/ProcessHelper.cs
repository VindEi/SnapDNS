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

            // Asynchronously read both streams in the background
            var outputTask = p.StandardOutput.ReadToEndAsync();
            var errorTask = p.StandardError.ReadToEndAsync();

            if (p.WaitForExit(10000))
            {
                string output = outputTask.GetAwaiter().GetResult();
                string error = errorTask.GetAwaiter().GetResult();

                if (p.ExitCode != 0 && logger != null)
                {
                    logger.LogWarning("CLI Error: {Cmd} Code {Code}. Output: {Out} Msg: {Msg}", cmd, p.ExitCode, output, error);
                }
                return p.ExitCode == 0;
            }
            else
            {
                try { p.Kill(); } catch { }
                logger?.LogWarning("Process execution timed out (10s) and was forcibly terminated: {Cmd}", cmd);
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