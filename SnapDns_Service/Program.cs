using SnapDns.Service.Ipc;
using SnapDns.Service.Services;

var builder = Host.CreateApplicationBuilder(args);

// Register Logic
builder.Services.AddSingleton<DnsProxyService>();
builder.Services.AddSingleton<SystemDnsService>();

// Register IPC Server
builder.Services.AddHostedService<PipeServer>();

// Platform Integration
if (OperatingSystem.IsWindows()) builder.Services.AddWindowsService();
if (OperatingSystem.IsLinux()) builder.Services.AddSystemd();

var host = builder.Build();
host.Run();