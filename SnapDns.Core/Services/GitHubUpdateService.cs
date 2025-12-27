using SnapDns.Core.Interfaces;
using System;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;

namespace SnapDns.Core.Services
{
    public class GitHubUpdateService : IUpdateService
    {
        private const string RepoOwner = "VindEi";
        private const string RepoName = "SnapDNS";

        private readonly HttpClient _httpClient;

        public string CurrentVersion { get; }

        public GitHubUpdateService()
        {
            _httpClient = new HttpClient();
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("SnapDns-Updater");
            _httpClient.Timeout = TimeSpan.FromMinutes(10); // Allow time for slow downloads

            var ver = Assembly.GetEntryAssembly()?.GetName().Version;
            CurrentVersion = ver != null ? $"{ver.Major}.{ver.Minor}.{ver.Build}" : "1.0.0";
        }

        public async Task<string?> CheckForUpdateAsync()
        {
            try
            {
                string apiUrl = $"https://api.github.com/repos/{RepoOwner}/{RepoName}/releases/latest";
                var response = await _httpClient.GetStringAsync(apiUrl);

                using var doc = JsonDocument.Parse(response);
                var root = doc.RootElement;

                string tagName = root.GetProperty("tag_name").GetString() ?? "";
                string htmlUrl = root.GetProperty("html_url").GetString() ?? "";

                if (string.IsNullOrWhiteSpace(tagName)) return null;

                string cleanTag = tagName.StartsWith("v", StringComparison.OrdinalIgnoreCase)
                    ? tagName[1..]
                    : tagName;

                if (Version.TryParse(cleanTag, out var latestVer) &&
                    Version.TryParse(CurrentVersion, out var currentVer))
                {
                    if (latestVer > currentVer)
                    {
                        // Look for the .exe asset
                        if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var asset in assets.EnumerateArray())
                            {
                                string name = asset.GetProperty("name").GetString() ?? "";
                                string downloadUrl = asset.GetProperty("browser_download_url").GetString() ?? "";

                                if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                                {
                                    return downloadUrl;
                                }
                            }
                        }
                        // Fallback to page URL if no exe found
                        return htmlUrl;
                    }
                }
            }
            catch { /* Ignore errors */ }

            return null;
        }

        public async Task DownloadInstallerAsync(string url, string destinationPath, IProgress<double> progress)
        {
            using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? -1L;
            var canReportProgress = totalBytes != -1;

            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

            var buffer = new byte[8192];
            long totalRead = 0;
            int bytesRead;

            while ((bytesRead = await contentStream.ReadAsync(buffer)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead));
                totalRead += bytesRead;

                if (canReportProgress)
                {
                    progress.Report((double)totalRead / totalBytes * 100);
                }
            }
        }
    }
}