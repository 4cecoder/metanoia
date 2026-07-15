// ─────────────────────────────────────────────────────────────────────
//  SetupWizardTests.cs  —  Unit tests for SetupWizard.cs
//  Target: .NET Framework 4.8  |  Style: Arrange-Act-Assert
//
//  Compile for test execution:
//      csc.exe /define:TEST /target:exe /main:MetanoiaSetup.Tests.TestRunner
//             /out:windows_helper\SetupWizardTests.exe
//             /reference:System.IO.Compression.dll
//             /reference:System.IO.Compression.FileSystem.dll
//             windows_helper\SetupWizard.cs
//             windows_helper\SetupWizardTests.cs
//
//  Without /define:TEST the test code is excluded and compilation
//  behaves identically to the production build.
//
//  Assertions use a custom Assert class (no NuGet packages needed).
// ─────────────────────────────────────────────────────────────────────

#if TEST

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;

namespace MetanoiaSetup.Tests
{
    // ═════════════════════════════════════════════════════════════════
    //  Custom assertion utility — mirrors nUnit/xUnit basic asserts
    //  without requiring any NuGet packages.
    // ═════════════════════════════════════════════════════════════════
    public class AssertFailedException : Exception
    {
        public AssertFailedException(string message) : base(message) { }
    }

    public static class Assert
    {
        public static void AreEqual<T>(T expected, T actual, string message = "")
        {
            if (!EqualityComparer<T>.Default.Equals(expected, actual))
            {
                var msg = $"  Expected: {expected}\n  Actual:   {actual}";
                if (!string.IsNullOrEmpty(message)) msg += $"\n  {message}";
                throw new AssertFailedException(msg);
            }
        }

        public static void AreNotEqual<T>(T notExpected, T actual, string message = "")
        {
            if (EqualityComparer<T>.Default.Equals(notExpected, actual))
            {
                var msg = $"  Expected not: {notExpected}\n  Actual:       {actual}";
                if (!string.IsNullOrEmpty(message)) msg += $"\n  {message}";
                throw new AssertFailedException(msg);
            }
        }

        public static void IsTrue(bool condition, string message = "")
        {
            if (!condition)
                throw new AssertFailedException(
                    $"  Expected True but got False. {message}".TrimEnd());
        }

        public static void IsFalse(bool condition, string message = "")
        {
            if (condition)
                throw new AssertFailedException(
                    $"  Expected False but got True. {message}".TrimEnd());
        }

        public static void IsNull(object obj, string message = "")
        {
            if (obj != null)
                throw new AssertFailedException(
                    $"  Expected null but got: {obj}. {message}".TrimEnd());
        }

        public static void IsNotNull(object obj, string message = "")
        {
            if (obj == null)
                throw new AssertFailedException(
                    $"  Expected non-null but got null. {message}".TrimEnd());
        }

        public static void Fail(string message)
        {
            throw new AssertFailedException($"  Assert.Fail: {message}");
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  Simple test attribute — marks methods as test cases.
    // ═════════════════════════════════════════════════════════════════
    [AttributeUsage(AttributeTargets.Method)]
    public class TestAttribute : Attribute { }

    // ═════════════════════════════════════════════════════════════════
    //  Test runner entry point
    //
    //  Discovers all [Test]-annotated methods on SetupWizardTests via
    //  reflection, executes them in order, and prints a summary.
    //  Returns exit code 0 (all pass) or 1 (any failure).
    // ═════════════════════════════════════════════════════════════════
    public static class TestRunner
    {
        private static int _passed;
        private static int _failed;
        private static readonly List<string> _errors = new List<string>();
        private static readonly Stopwatch _watch = new Stopwatch();

        public static void Main()
        {
            Console.WriteLine();
            Console.WriteLine("  ╔══════════════════════════════════════════════════╗");
            Console.WriteLine("  ║   Metanoia — SetupWizard Unit Tests            ║");
            Console.WriteLine("  ║   .NET Framework {0,-28} ║", Environment.Version);
            Console.WriteLine("  ║   {0,-37} ║", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
            Console.WriteLine("  ╚══════════════════════════════════════════════════╝");
            Console.WriteLine();

            var testClass = typeof(SetupWizardTests);
            var methods = testClass
                .GetMethods(BindingFlags.Public | BindingFlags.Instance)
                .Where(m => m.GetCustomAttribute<TestAttribute>() != null)
                .OrderBy(m => m.Name)
                .ToArray();

            if (methods.Length == 0)
            {
                Console.WriteLine("  ⚠  No [Test] methods found on SetupWizardTests.");
                Environment.Exit(1);
                return;
            }

            var instance = Activator.CreateInstance(testClass);
            _watch.Start();

            foreach (var method in methods)
            {
                Console.Write($"  ► {method.Name}  ...  ");
                var start = _watch.ElapsedMilliseconds;

                try
                {
                    method.Invoke(instance, null);
                    var elapsed = _watch.ElapsedMilliseconds - start;
                    Console.WriteLine($"PASS  ({elapsed} ms)");
                    _passed++;
                }
                catch (TargetInvocationException tie)
                {
                    var elapsed = _watch.ElapsedMilliseconds - start;
                    var actualEx = tie.InnerException;

                    if (actualEx is AssertFailedException afe)
                    {
                        Console.WriteLine($"FAIL  ({elapsed} ms)");
                        Console.WriteLine($"  {afe.Message.Replace("\n", "\n  ")}");
                        _failed++;
                        _errors.Add($"{method.Name} — {afe.Message}");
                    }
                    else
                    {
                        Console.WriteLine($"ERROR  ({elapsed} ms)");
                        Console.WriteLine($"  {actualEx.GetType().Name}: {actualEx.Message}");
                        _failed++;
                        _errors.Add($"{method.Name} — UNHANDLED {actualEx.GetType().Name}: {actualEx.Message}");
                    }
                }
                catch (Exception ex)
                {
                    var elapsed = _watch.ElapsedMilliseconds - start;
                    Console.WriteLine($"ERROR  ({elapsed} ms)");
                    Console.WriteLine($"  {ex.GetType().Name}: {ex.Message}");
                    _failed++;
                    _errors.Add($"{method.Name} — UNHANDLED {ex.GetType().Name}: {ex.Message}");
                }
            }

            _watch.Stop();
            var total = _passed + _failed;

            Console.WriteLine();
            Console.WriteLine("  ────────────────────────────────────────────────────");
            Console.WriteLine($"  {total} test(s)  |  ✓ {_passed} passed  |  ✗ {_failed} failed  |  {_watch.ElapsedMilliseconds} ms");
            Console.WriteLine();

            if (_errors.Count > 0)
            {
                Console.WriteLine("  Failures:");
                foreach (var err in _errors)
                {
                    // Only first line of each error
                    var firstLine = err.Split('\n')[0];
                    Console.WriteLine($"    ✗  {firstLine}");
                }
                Console.WriteLine();
            }

            Environment.Exit(_failed > 0 ? 1 : 0);
        }
    }

    // ═════════════════════════════════════════════════════════════════
    //  Test fixture
    //
    //  Each [Test] method follows the Arrange / Act / Assert pattern.
    //  Tests interact with the public API of MetanoiaSetup classes.
    // ═════════════════════════════════════════════════════════════════
    public class SetupWizardTests
    {
        // ─────────────────────────────────────────────────────────────
        //  Test 1: SystemScanner.FindOnPath
        //
        //  Verifies that FindOnPath can resolve a well-known system
        //  executable (cmd.exe) through the PATH and capture its
        //  --version output.
        // ─────────────────────────────────────────────────────────────
        [Test]
        public void SystemScanner_FindOnPath_WithKnownExe_ReturnsFound()
        {
            // Arrange
            var scanner = new SystemScanner();
            const string knownExe = "cmd.exe";

            // Act
            var result = scanner.FindOnPath(knownExe).GetAwaiter().GetResult();

            // Assert
            Assert.IsTrue(result.Found,
                $"'{knownExe}' should resolve on PATH. Error: {result.Error}");
            Assert.IsNotNull(result.Version,
                "Version string should not be null when executable is found");
            Assert.IsTrue(result.Version.Length > 0,
                "Version string should be non-empty when executable responds to --version");

            // Additional structural checks on CheckResult
            Assert.IsNull(result.Error,
                "Error should be null when check succeeds");
            Assert.IsFalse(string.IsNullOrWhiteSpace(result.Version),
                "Version should contain meaningful text");
        }


        // ─────────────────────────────────────────────────────────────
        //  Test 2: SystemScanner.GetMsys2Path
        //
        //  Validates that GetMsys2Path returns null when no MSYS2
        //  installation exists, or one of the three known candidate
        //  paths if an installation IS present.  Also confirms the
        //  candidate ordering (msys64 before msys2 before tools).
        // ─────────────────────────────────────────────────────────────
        [Test]
        public void SystemScanner_GetMsys2Path_ReturnsExpectedCandidateOrNull()
        {
            // Arrange
            var scanner = new SystemScanner();
            var expectedCandidates = new[]
            {
                @"C:\msys64",
                @"C:\msys2",
                @"C:\tools\msys64"
            };

            // Act
            var result = scanner.GetMsys2Path();

            // Assert
            // Must be null (none found) or exactly one of the known candidates.
            Assert.IsTrue(
                result == null
                    || expectedCandidates.Contains(result, StringComparer.OrdinalIgnoreCase),
                $"Path '{result}' is not a valid MSYS2 candidate. "
                    + $"Expected null or one of: {string.Join(", ", expectedCandidates)}"
            );

            // Contract: if non-null, the directory must actually exist on disk.
            if (result != null)
            {
                Assert.IsTrue(
                    Directory.Exists(result),
                    $"Returned path '{result}' should exist on disk"
                );

                // Candidate ordering: the first existing path in the array wins.
                var firstExisting = expectedCandidates.FirstOrDefault(Directory.Exists);
                Assert.AreEqual(
                    firstExisting,
                    result,
                    "GetMsys2Path should return the FIRST existing candidate"
                );
            }
        }


        // ─────────────────────────────────────────────────────────────
        //  Test 3: SystemScanner.IsOnPath
        //
        //  Verifies that IsOnPath correctly identifies directories
        //  present in the PATH environment variable and rejects
        //  directories that are not present.  Also confirms the
        //  comparison is case-insensitive (Windows convention).
        // ─────────────────────────────────────────────────────────────
        [Test]
        public void SystemScanner_IsOnPath_DetectsDirectoryCorrectly()
        {
            // Arrange
            var scanner = new SystemScanner();
            var systemDir = Environment.GetFolderPath(Environment.SpecialFolder.System);
            var fakeDir = Path.Combine(
                Path.GetTempPath(),
                "MetanoiaFakePath_" + Guid.NewGuid().ToString("N")
            );

            // Guard: fake directory must NOT exist for test validity
            Assert.IsFalse(Directory.Exists(fakeDir),
                "Test invariant: fake directory should not exist on disk; it is unrelated to PATH membership");

            // Act
            var positiveResult = scanner.IsOnPath(systemDir);
            var negativeResult = scanner.IsOnPath(fakeDir);
            var caseInsensitiveResult = scanner.IsOnPath(systemDir.ToUpperInvariant());

            // Assert
            Assert.IsTrue(positiveResult,
                $"System directory '{systemDir}' is expected to be on PATH");

            Assert.IsFalse(negativeResult,
                $"Non-existent directory '{fakeDir}' must not appear on PATH");

            Assert.IsTrue(caseInsensitiveResult,
                "IsOnPath should perform case-insensitive comparison "
                    + $"(found '{systemDir}' on PATH, but uppercase lookup failed)");
        }


        // ─────────────────────────────────────────────────────────────
        //  Test 4: PathManager.AddToUserPath
        //
        //  Validates that AddToUserPath appends a directory to the
        //  User-level PATH and, crucially, does NOT create a duplicate
        //  entry when called a second time with the same directory.
        //
        //  Environment state is saved before the test and restored
        //  unconditionally in the finally block.
        // ─────────────────────────────────────────────────────────────
        [Test]
        public void PathManager_AddToUserPath_DoesNotDuplicate()
        {
            // Arrange
            var manager = new PathManager();
            var testDir = Path.Combine(
                Path.GetTempPath(),
                "MetanoiaTestPath_" + Guid.NewGuid().ToString("N")
            );

            // Snapshot current environment state
            var originalUserPath =
                Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";
            var originalProcessPath =
                Environment.GetEnvironmentVariable("PATH") ?? "";

            try
            {
                // ── Act (first call) ────────────────────────────────
                manager.AddToUserPath(testDir);

                var afterFirstAdd =
                    Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";

                // ── Assert (first call) ─────────────────────────────
                Assert.IsTrue(
                    afterFirstAdd
                        .Split(';')
                        .Any(p => p.Trim()
                            .Equals(testDir, StringComparison.OrdinalIgnoreCase)),
                    $"PATH should contain '{testDir}' after the first AddToUserPath call"
                );

                // ── Act (second call — should de-duplicate) ────────
                manager.AddToUserPath(testDir);

                var afterSecondAdd =
                    Environment.GetEnvironmentVariable("PATH", EnvironmentVariableTarget.User) ?? "";

                var occurrences = afterSecondAdd
                    .Split(';')
                    .Count(p => p.Trim()
                        .Equals(testDir, StringComparison.OrdinalIgnoreCase));

                // ── Assert (deduplication) ─────────────────────────
                Assert.AreEqual(1, occurrences,
                    $"Path '{testDir}' should appear exactly ONCE after duplicate add, "
                        + $"but found {occurrences} occurrence(s). "
                        + "AddToUserPath must guard against duplicate entries.");
            }
            finally
            {
                // ── Cleanup ─────────────────────────────────────────
                Environment.SetEnvironmentVariable(
                    "PATH", originalUserPath, EnvironmentVariableTarget.User);
                Environment.SetEnvironmentVariable(
                    "PATH", originalProcessPath);
            }
        }


        // ─────────────────────────────────────────────────────────────
        //  Test 5: BuildRunner.Run
        //
        //  Verifies that BuildRunner.Run handles the case where the
        //  'zig' executable is not resolvable (returns false, logs an
        //  error message).  If zig IS on PATH, the build will still
        //  fail because the temp working directory does not contain a
        //  build.zig manifest — so the method returns false either way.
        //
        //  Also confirms that the OnLog event fires at least once.
        // ─────────────────────────────────────────────────────────────
        [Test]
        public void BuildRunner_Run_WhenZigBuildFails_ReturnsFalse()
        {
            // Arrange
            var runner = new BuildRunner();
            var logLines = new List<string>();
            runner.OnLog += msg => logLines.Add(msg);

            // Use a dedicated subdirectory that definitely has no build.zig
            var workDir = Path.Combine(
                Path.GetTempPath(),
                "MetanoiaBuildTest_" + Guid.NewGuid().ToString("N")
            );
            Directory.CreateDirectory(workDir);
            Assert.IsFalse(
                File.Exists(Path.Combine(workDir, "build.zig")),
                "Test invariant: workDir must not contain build.zig"
            );

            try
            {
                // Act
                var result = runner.Run(workDir).GetAwaiter().GetResult();

                // Assert
                Assert.IsFalse(result,
                    "BuildRunner.Run should return false when 'zig build' cannot succeed "
                    + "(zig not on PATH, or no build.zig in working directory)");

                Assert.IsTrue(logLines.Count > 0,
                    "At least one log message should have been emitted by BuildRunner");

                Assert.IsTrue(
                    logLines.Any(l => l.IndexOf("zig build", StringComparison.OrdinalIgnoreCase) >= 0),
                    "The log should contain the 'zig build' invocation header. "
                    + $"Got: [{string.Join(" | ", logLines)}]");
            }
            finally
            {
                // Cleanup temp directory
                try { Directory.Delete(workDir, recursive: true); }
                catch { /* best-effort cleanup */ }
            }
        }
    }
}

#endif
