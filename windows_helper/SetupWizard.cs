using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MetanoiaSetup
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }

    public class CheckResult
    {
        public bool Found;
        public string Version;
        public string Error;
    }

    // ── Scanner ──────────────────────────────────────────────────
    public class SystemScanner
    {
        public async Task<CheckResult> FindOnPath(string name, string versionArg = "--version")
        {
            var exe = await ResolvePath(name);
            if (exe == null)
                return new CheckResult { Found = false, Error = $"'{name}' not found on PATH" };
            var ver = RunAndRead(exe, versionArg);
            return new CheckResult { Found = true, Version = ver?.Trim() };
        }

        public Task<bool> FileExists(string path)
        {
            return Task.FromResult(File.Exists(path));
        }

        public Task<bool> DirExists(string path)
        {
            return Task.FromResult(Directory.Exists(path));
        }

        public CheckResult RunFile(string path, string args)
        {
            if (!File.Exists(path))
                return new CheckResult { Found = false, Error = $"File not found: {path}" };
            var ver = RunAndRead(path, args);
            return new CheckResult { Found = ver != null, Version = ver?.Trim() };
        }

        public string GetMsys2Path()
        {
            var candidates = new[] { @"C:\msys64", @"C:\msys2", @"C:\tools\msys64" };
            return candidates.FirstOrDefault(Directory.Exists);
        }

        public bool IsOnPath(string dir)
        {
            var path = Environment.GetEnvironmentVariable("PATH") ?? "";
            return path.Split(';').Any(p => p.Trim().Equals(dir, StringComparison.OrdinalIgnoreCase));
        }

        private async Task<string> ResolvePath(string name)
        {
            try
            {
                var psi = new ProcessStartInfo("where", name)
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var p = Process.Start(psi);
                if (p == null) return null;
                var lines = await p.StandardOutput.ReadToEndAsync();
                p.WaitForExit();
                if (p.ExitCode != 0) return null;
                return lines.Trim().Split('\n').FirstOrDefault()?.Trim();
            }
            catch { return null; }
        }

        private string RunAndRead(string exe, string args)
        {
            try
            {
                var psi = new ProcessStartInfo(exe, args)
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                var p = Process.Start(psi);
                if (p == null) return null;
                var output = p.StandardOutput.ReadToEnd();
                p.WaitForExit(5000);
                return p.ExitCode == 0 ? output : null;
            }
            catch { return null; }
        }
    }

    // ── Installer ───────────────────────────────────────────────
    public class ToolInstaller
    {
        public event Action<string> OnLog;

        public async Task<string> GetLatestZigUrl()
        {
            try
            {
                var json = await new WebClient().DownloadStringTaskAsync("https://ziglang.org/download/index.json");
                // Parse: find "master" -> "x86_64-windows" -> "tarball" value
                var masterKey = "\"master\"";
                var winKey = "\"x86_64-windows\"";
                var tarballKey = "\"tarball\"";
                var masterIdx = json.IndexOf(masterKey, StringComparison.Ordinal);
                if (masterIdx < 0) return null;
                var winIdx = json.IndexOf(winKey, masterIdx, StringComparison.Ordinal);
                if (winIdx < 0) return null;
                var tarballIdx = json.IndexOf(tarballKey, winIdx, StringComparison.Ordinal);
                if (tarballIdx < 0) return null;
                var valStart = json.IndexOf('"', tarballIdx + tarballKey.Length + 1) + 1;
                if (valStart <= 0) return null;
                var valEnd = json.IndexOf('"', valStart);
                if (valEnd <= valStart) return null;
                return json.Substring(valStart, valEnd - valStart);
            }
            catch (Exception ex) { Log($"Failed to fetch Zig version: {ex.Message}"); return null; }
        }

        public async Task<bool> DownloadZipExtract(string url, string destDir, string exeName, string label)
        {
            Directory.CreateDirectory(destDir);
            var zipPath = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".zip");
            try
            {
                Log($"Downloading {label}...");
                using (var wc = new WebClient())
                    await wc.DownloadFileTaskAsync(new Uri(url), zipPath);
                Log($"Extracting to {destDir}...");
                if (Directory.Exists(destDir))
                    Directory.Delete(destDir, recursive: true);
                ZipFile.ExtractToDirectory(zipPath, destDir);
                var exePath = Directory.GetDirectories(destDir)
                    .Select(d => Path.Combine(d, exeName))
                    .Concat(new[] { Path.Combine(destDir, exeName) })
                    .FirstOrDefault(File.Exists);
                if (exePath != null)
                {
                    new PathManager().AddToUserPath(Path.GetDirectoryName(exePath));
                    Log($"{label} installed. Added to PATH.");
                    return true;
                }
                Log($"{label}: exe not found after extraction.");
                return false;
            }
            catch (Exception ex) { Log($"{label} failed: {ex.Message}"); return false; }
            finally { TryDelete(zipPath); }
        }

        public async Task<bool> InstallMsys2(string url, string installDir)
        {
            var exePath = Path.Combine(Path.GetTempPath(), "msys2-installer.exe");
            try
            {
                Log("Downloading MSYS2...");
                using (var wc = new WebClient())
                    await wc.DownloadFileTaskAsync(new Uri(url), exePath);
                Log("Running installer...");
                var psi = new ProcessStartInfo(exePath, $"install --quiet --root \"{installDir}\"")
                { UseShellExecute = true, CreateNoWindow = true };
                var p = Process.Start(psi);
                if (p != null) p.WaitForExit();

                Log("Installing GTK4 + dependencies...");
                var pacman = Path.Combine(installDir, "ucrt64.exe");
                if (!File.Exists(pacman))
                { Log("MSYS2 installed but ucrt64.exe not found."); return false; }

                var packages = "mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3 mingw-w64-ucrt-x86_64-curl";
                var pi = new ProcessStartInfo(pacman, $"-S --noconfirm {packages}")
                { UseShellExecute = true, CreateNoWindow = true };
                var proc = Process.Start(pi);
                if (proc != null) proc.WaitForExit();

                var binDir = Path.Combine(installDir, "ucrt64", "bin");
                new PathManager().AddToUserPath(binDir);
                Log($"MSYS2 + GTK4 installed. {binDir} added to PATH.");
                return true;
            }
            catch (Exception ex) { Log($"MSYS2 install failed: {ex.Message}"); return false; }
            finally { TryDelete(exePath); }
        }

        private void Log(string m) { if (OnLog != null) OnLog(m); }
        private void TryDelete(string p) { try { File.Delete(p); } catch { } }
    }

    // ── Path Manager ────────────────────────────────────────────
    public class PathManager
    {
        public void AddToUserPath(string dir)
        {
            try
            {
                var current = Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
                if (current.Split(';').Any(p => p.Equals(dir, StringComparison.OrdinalIgnoreCase)))
                    return;
                var updated = current.TrimEnd(';') + ";" + dir;
                Environment.SetEnvironmentVariable("PATH", updated, EnvironmentVariableTarget.User);
                Environment.SetEnvironmentVariable("PATH",
                    (Environment.GetEnvironmentVariable("PATH") ?? "") + ";" + dir);
            }
            catch { }
        }
    }

    // ── Build Runner ────────────────────────────────────────────
    public class BuildRunner
    {
        public event Action<string> OnLog;

        public bool Run(string workingDir)
        {
            Log(">>> zig build");
            try
            {
                var psi = new ProcessStartInfo("zig", "build")
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = workingDir
                };
                var p = Process.Start(psi);
                if (p == null) { Log("zig not found on PATH."); return false; }
                var output = p.StandardOutput.ReadToEnd();
                var error = p.StandardError.ReadToEnd();
                p.WaitForExit(120000);
                if (!string.IsNullOrEmpty(output)) Log(output);
                if (!string.IsNullOrEmpty(error)) Log("ERR: " + error);
                Log(p.ExitCode == 0 ? "BUILD SUCCESS" : $"BUILD FAILED (exit {p.ExitCode})");
                return p.ExitCode == 0;
            }
            catch (Exception ex) { Log($"Build error: {ex.Message}"); return false; }
        }

        private void Log(string m) { if (OnLog != null) OnLog(m); }
    }

    // ── Main Form ───────────────────────────────────────────────
    public class MainForm : Form
    {
        private readonly SystemScanner _scanner = new SystemScanner();
        private readonly ToolInstaller _installer = new ToolInstaller();
        private readonly BuildRunner _builder = new BuildRunner();
        private readonly PathManager _pathman = new PathManager();

        private readonly Dictionary<string, PrereqRow> _rows = new Dictionary<string, PrereqRow>();
        private FlowLayoutPanel _statusPanel;
        private RichTextBox _logBox;
        private Button _buildBtn, _vscodeBtn, _logBtn, _refreshBtn;
        private bool _logVisible;

        private static readonly Color Bg = Color.FromArgb(26, 27, 38);
        private static readonly Color Surface = Color.FromArgb(36, 40, 59);
        private static readonly Color Blue = Color.FromArgb(122, 162, 247);
        private static readonly Color Green = Color.FromArgb(158, 206, 106);
        private static readonly Color Red = Color.FromArgb(247, 118, 142);
        private static readonly Color Fg = Color.FromArgb(192, 202, 245);
        private static readonly Color Dim = Color.FromArgb(86, 95, 137);

        private class PrereqRow
        {
            public Label Status;
            public Label Name;
            public Button Action;
        }

        public MainForm()
        {
            Text = "Metanoia — Windows Setup";
            Size = new Size(680, 540);
            MinimumSize = new Size(580, 400);
            BackColor = Bg;
            ForeColor = Fg;
            Font = new Font("Segoe UI", 10);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;

            _installer.OnLog += Log;
            _builder.OnLog += Log;

            BuildUI();
            this.Load += async (_, _) => { try { await RefreshAll(); } catch (Exception ex) { Log($"Init: {ex.Message}"); } };
        }

        private void BuildUI()
        {
            var root = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 1,
                Padding = new Padding(16),
                BackColor = Bg
            };
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 36));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

            root.Controls.Add(new Label
            {
                Text = "Metanoia — Windows Setup",
                Font = new Font("Segoe UI", 16, FontStyle.Bold),
                ForeColor = Blue,
                BackColor = Bg
            }, 0, 0);

            _statusPanel = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                Dock = DockStyle.Fill,
                BackColor = Bg,
                AutoSize = true
            };
            root.Controls.Add(_statusPanel, 0, 1);

            AddPrereq("zig", "Zig Compiler");
            AddPrereq("msys2", "MSYS2 + UCRT64");
            AddPrereq("gtk4", "GTK4 (pkg-config)");
            AddPrereq("curl", "curl");
            AddPrereq("git", "Git");
            AddPrereq("vscode", "VS Code (optional)");

            var actions = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.LeftToRight,
                Dock = DockStyle.Fill,
                Padding = new Padding(0, 4, 0, 4),
                BackColor = Bg
            };

            _buildBtn = StyledBtn("Build Project", Green);
            _buildBtn.Click += (_, _) => { _buildBtn.Enabled = false; try { _builder.Run(Application.StartupPath); } catch (Exception ex) { Log(ex.Message); } finally { _buildBtn.Enabled = true; } };
            _vscodeBtn = StyledBtn("Open in VS Code", Blue);
            _vscodeBtn.Click += (_, _) => LaunchVSCode();
            _logBtn = StyledBtn("Show Log", Dim);
            _logBtn.Click += (_, _) => ToggleLog();
            _refreshBtn = StyledBtn("Refresh", Fg);
            _refreshBtn.Click += async (_, _) => { try { await RefreshAll(); } catch (Exception ex) { Log($"Refresh: {ex.Message}"); } };

            actions.Controls.AddRange(new Control[] { _buildBtn, _vscodeBtn, _logBtn, _refreshBtn });
            root.Controls.Add(actions, 0, 2);

            _logBox = new RichTextBox
            {
                Dock = DockStyle.Fill,
                BackColor = Surface,
                ForeColor = Fg,
                Font = new Font("Cascadia Code", 9),
                ReadOnly = true,
                Visible = false,
                BorderStyle = BorderStyle.None
            };
            root.Controls.Add(_logBox, 0, 3);

            Controls.Add(root);
        }

        private void AddPrereq(string key, string label)
        {
            var row = new TableLayoutPanel
            {
                ColumnCount = 3,
                Dock = DockStyle.Fill,
                AutoSize = true,
                BackColor = Bg
            };
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 28));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));

            var status = new Label { Text = "○", ForeColor = Dim, AutoSize = true, Font = new Font("Segoe UI", 12), TextAlign = ContentAlignment.MiddleLeft };
            var name = new Label { Text = label, ForeColor = Fg, AutoSize = true, Padding = new Padding(4, 2, 0, 2), TextAlign = ContentAlignment.MiddleLeft };
            var action = new Button
            {
                Text = "Scanning...", FlatStyle = FlatStyle.Flat, ForeColor = Dim,
                BackColor = Surface, Height = 26, Width = 85,
                FlatAppearance = { BorderSize = 0 }, Cursor = Cursors.Hand, Enabled = false,
                Font = new Font("Segoe UI", 8)
            };

            row.Controls.Add(status);
            row.Controls.Add(name);
            row.Controls.Add(action);
            _statusPanel.Controls.Add(row);

            _rows[key] = new PrereqRow { Status = status, Name = name, Action = action };
        }

        private Button StyledBtn(string text, Color color)
        {
            return new Button
            {
                Text = text,
                FlatStyle = FlatStyle.Flat,
                BackColor = color,
                ForeColor = Color.White,
                Font = new Font("Segoe UI", 9, FontStyle.Bold),
                Height = 30,
                AutoSize = true,
                Padding = new Padding(12, 0, 12, 0),
                FlatAppearance = { BorderSize = 0 },
                Cursor = Cursors.Hand
            };
        }

        private async Task RefreshAll()
        {
            await Task.WhenAll(
                CheckZig(),
                CheckMsys2(),
                CheckGtk4(),
                CheckCurl(),
                CheckGit(),
                CheckVSCode()
            );
        }

        private void SetStatus(string key, bool ok, string detail, string actionText, Func<Task> onAction)
        {
            if (!_rows.TryGetValue(key, out var row)) return;
            row.Status.Text = ok ? "●" : "○";
            row.Status.ForeColor = ok ? Green : Red;
            row.Name.Text = detail != null ? $"{GetLabel(key)}  ({detail})" : GetLabel(key);

            if (ok || onAction == null)
            {
                row.Action.Visible = false;
            }
            else
            {
                row.Action.Text = actionText ?? "Install";
                row.Action.ForeColor = Blue;
                row.Action.Enabled = true;
                row.Action.Click -= OnInstallClick;
                row.Action.Click += OnInstallClick;
                row.Action.Tag = onAction;
            }
        }

        private string GetLabel(string key)
        {
            switch (key)
            {
                case "zig": return "Zig Compiler";
                case "msys2": return "MSYS2 + UCRT64";
                case "gtk4": return "GTK4 (pkg-config)";
                case "curl": return "curl";
                case "git": return "Git";
                case "vscode": return "VS Code (optional)";
                default: return key;
            }
        }

        private async void OnInstallClick(object sender, EventArgs e)
        {
            var btn = sender as Button;
            if (btn == null) return;
            var action = btn.Tag as Func<Task>;
            if (action == null) return;
            btn.Enabled = false;
            btn.Text = "Working...";
            try { await action(); }
            catch (Exception ex) { Log($"Error: {ex.Message}"); }
            await RefreshAll();
        }

        private async Task CheckZig()
        {
            var r = await _scanner.FindOnPath("zig");
            SetStatus("zig", r.Found, r.Version, "Download", async () =>
            {
                var url = await _installer.GetLatestZigUrl();
                if (url == null) { Log("Could not determine latest Zig version."); return; }
                Log($"Latest Zig: {url}");
                await _installer.DownloadZipExtract(
                    url,
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "zig"),
                    "zig.exe", "Zig");
            });
        }

        private async Task CheckMsys2()
        {
            var msysDir = _scanner.GetMsys2Path();
            var ok = msysDir != null;
            SetStatus("msys2", ok, ok ? msysDir : null, "Install", async () =>
            {
                await _installer.InstallMsys2(
                    "https://github.com/msys2/msys2-installer/releases/download/2025-04-14/msys2-x86_64-20250414.exe",
                    @"C:\msys64");
            });
        }

        private async Task CheckGtk4()
        {
            var msysDir = _scanner.GetMsys2Path();
            if (msysDir == null)
            { SetStatus("gtk4", false, null, "Install MSYS2 first", null); return; }
            var pkgConfig = Path.Combine(msysDir, "ucrt64", "bin", "pkg-config.exe");
            var r = _scanner.RunFile(pkgConfig, "--modversion gtk4");
            SetStatus("gtk4", r.Found, r.Version, "Install", async () =>
            {
                var pacman = Path.Combine(msysDir, "ucrt64.exe");
                if (!File.Exists(pacman)) return;
                var pi = new ProcessStartInfo(pacman,
                    "-S --noconfirm mingw-w64-ucrt-x86_64-gtk4 mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-sqlite3 mingw-w64-ucrt-x86_64-curl")
                { UseShellExecute = true, CreateNoWindow = true };
                var p = Process.Start(pi);
                if (p != null) p.WaitForExit();
                var binDir = Path.Combine(msysDir, "ucrt64", "bin");
                _pathman.AddToUserPath(binDir);
            });
            if (!r.Found && msysDir != null)
            {
                var binDir = Path.Combine(msysDir, "ucrt64", "bin");
                if (!_scanner.IsOnPath(binDir))
                    Log($"HINT: Add {binDir} to your PATH for pkg-config to work.");
            }
        }

        private async Task CheckCurl()
        {
            var r = await _scanner.FindOnPath("curl");
            SetStatus("curl", r.Found, r.Version, null, null);
        }

        private async Task CheckGit()
        {
            var r = await _scanner.FindOnPath("git");
            SetStatus("git", r.Found, r.Version, null, null);
        }

        private async Task CheckVSCode()
        {
            var paths = new[]
            {
                @"C:\Program Files\Microsoft VS Code\Code.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs\\Microsoft VS Code\\Code.exe")
            };
            var ok = paths.Any(File.Exists);
            SetStatus("vscode", ok, ok ? "found" : null, null, null);
        }

        private void LaunchVSCode()
        {
            var paths = new[]
            {
                @"C:\Program Files\Microsoft VS Code\Code.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs\\Microsoft VS Code\\Code.exe")
            };
            var code = paths.FirstOrDefault(File.Exists);
            if (code != null)
                Process.Start(new ProcessStartInfo(code, ".") { WorkingDirectory = Application.StartupPath });
            else
                Log("VS Code not found.");
        }

        private void ToggleLog()
        {
            _logVisible = !_logVisible;
            _logBox.Visible = _logVisible;
            _logBtn.Text = _logVisible ? "Hide Log" : "Show Log";
        }

        private void Log(string msg)
        {
            var line = $"[{DateTime.Now:HH:mm:ss}] {msg}";
            if (_logBox.InvokeRequired)
                _logBox.Invoke(new Action(() => _logBox.AppendText(line + "\n")));
            else
                _logBox.AppendText(line + "\n");
            Debug.WriteLine(line);
        }
    }
}
