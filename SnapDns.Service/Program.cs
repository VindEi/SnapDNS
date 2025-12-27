using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using SnapDns.Service.Ipc;
using SnapDns.Service.Services;
using System.Diagnostics;
using System.Runtime.InteropServices;

var builder = Host.CreateApplicationBuilder(args);

// --- Platform-Specific Configuration ---
if (!Debugger.IsAttached)
{
    if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
    {
        builder.Services.AddWindowsService();

        // Fix ContentRootPath for Windows Services
        var pathToExe = Process.GetCurrentProcess().MainModule?.FileName;
        var pathToContentRoot = Path.GetDirectoryName(pathToExe);

        if (!string.IsNullOrEmpty(pathToContentRoot))
        {
            builder.Environment.ContentRootPath = pathToContentRoot;
            Directory.SetCurrentDirectory(pathToContentRoot);
        }
    }
    else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
    {
        builder.Services.AddSystemd();
    }
}

// --- Logging ---
builder.Logging.ClearProviders();
builder.Logging.AddConsole();
builder.Logging.AddDebug();

// --- Service Registration ---
builder.Services.AddSingleton<DnsProxyService>();
builder.Services.AddSingleton<SystemDnsService>();
builder.Services.AddHostedService<PipeServer>();

var host = builder.Build();
host.Run();