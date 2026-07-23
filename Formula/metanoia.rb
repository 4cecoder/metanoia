# Formula/metanoia.rb
#
# Homebrew formula for Metanoia (Zig + GTK4 Bible study app), using the
# binary-download pattern — it fetches the prebuilt Metanoia-macos-<arch>.tar.gz
# asset produced by .github/workflows/release-unix.yml / packaging/build-macos.sh,
# it does NOT build from source (no Zig toolchain dependency needed at install time).
#
# This formula lives in this repo for convenience, but Homebrew formulae must
# be installed from a "tap" (a separate Git repo Homebrew knows how to find,
# named `homebrew-<something>`). This repo is NOT a tap. url/version/sha256
# below are real and current (release 2026.07.23-f04ce77, verified via
# `shasum -a 256` against the actual downloaded asset) — release-unix.yml's
# `permissions: contents: write` gap (it could never actually publish a
# release before that was fixed) is resolved, so re-cutting this against a
# newer tag later is just: push a new "20*.*.*" tag, then update url/version/
# sha256 here from that release the same way.
#
# Still needed before `brew install` actually works for anyone:
#   1. Create a new GitHub repo named `homebrew-metanoia` under the 4cecoder
#      org/user (Homebrew's naming convention: homebrew-<tap-name>).
#   2. Copy this file into that repo at Formula/metanoia.rb.
#   3. Users then run: brew tap 4cecoder/metanoia && brew install metanoia
#
# To compute the sha256 for a future release:
#   curl -fsSL -o /tmp/Metanoia-macos-arm64.tar.gz \
#     https://github.com/4cecoder/metanoia/releases/download/<TAG>/Metanoia-macos-arm64.tar.gz
#   shasum -a 256 /tmp/Metanoia-macos-arm64.tar.gz
#
# NOTE: release-unix.yml's build-macos job only runs on macos-latest (Apple
# Silicon / arm64 GitHub-hosted runner), so today only an arm64 tarball
# exists. Intel (x86_64) Mac support would need an additional macos-13 (or
# similar Intel) runner added to the CI matrix — not done today, follow-up.

class Metanoia < Formula
  desc "Bible study app (Zig + GTK4, Tokyo Night themed)"
  homepage "https://github.com/4cecoder/metanoia"

  if Hardware::CPU.arm?
    url "https://github.com/4cecoder/metanoia/releases/download/2026.07.23-f04ce77/Metanoia-macos-arm64.tar.gz"
    version "2026.07.23-f04ce77"
    sha256 "f233b59018ab41ccbc5f6fc1f1a2d4ffd4e3bcdb0cb63af8c01c15da2e5f0a03"
  else
    odie "Metanoia: no prebuilt Intel (x86_64) macOS build is published yet. " \
         "See Formula/metanoia.rb for how to add one."
  end

  depends_on "gtk4"
  depends_on "sqlite3"

  def install
    # Install the whole .app bundle under libexec, unmodified, so
    # resolveBundleRoot() in src/main.zig still finds ".app/Contents/MacOS/"
    # in the running binary's own path and chdirs to Contents/Resources
    # (where data/bible.db and assets/ live) exactly like a double-clicked
    # .app would. Then expose a plain `metanoia` binary on PATH via a
    # wrapper that exec's the real binary directly (not through a symlink,
    # so _NSGetExecutablePath still resolves inside the installed bundle).
    libexec.install "Metanoia.app"

    (bin/"metanoia").write <<~SH
      #!/bin/bash
      exec "#{libexec}/Metanoia.app/Contents/MacOS/metanoia" "$@"
    SH
    (bin/"metanoia").chmod 0755
  end

  def caveats
    <<~EOS
      Metanoia ships ad-hoc signed, not notarized (no paid Apple Developer
      cert is used for this build). If macOS Gatekeeper refuses to launch it:
        xattr -cr #{libexec}/Metanoia.app

      Run it with:
        metanoia
    EOS
  end

  test do
    assert_predicate bin/"metanoia", :exist?
  end
end
