# Formula/metanoia.rb
#
# Homebrew formula for Metanoia (Zig + GTK4 Bible study app), using the
# binary-download pattern — it fetches the prebuilt Metanoia-macos-<arch>.tar.gz
# asset produced by .github/workflows/release-unix.yml / packaging/build-macos.sh,
# it does NOT build from source (no Zig toolchain dependency needed at install time).
#
# This formula lives in this repo for convenience, but Homebrew formulae must
# be installed from a "tap" (a separate Git repo Homebrew knows how to find,
# named `homebrew-<something>`). This repo is NOT a tap. Before this formula
# is usable via `brew install`, you (the maintainer) need to:
#   1. Create a new GitHub repo named `homebrew-metanoia` under the 4cecoder org/user
#      (Homebrew's naming convention: homebrew-<tap-name>).
#   2. Copy this file into that repo at Formula/metanoia.rb.
#   3. Cut a real release (push a "20*.*.*" tag) so release-unix.yml uploads
#      Metanoia-macos-arm64.tar.gz to a GitHub Release.
#   4. Fill in the TODOs below (url version + sha256) from that release.
#   5. Users then run: brew tap 4cecoder/metanoia && brew install metanoia
#
# To compute the sha256 once a release exists:
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
    # TODO: fill in after first release is cut (see instructions above).
    url "https://github.com/4cecoder/metanoia/releases/download/CHANGEME_TAG/Metanoia-macos-arm64.tar.gz"
    version "CHANGEME_TAG"
    # TODO: sha256 "<fill in after first release>"
    sha256 "0000000000000000000000000000000000000000000000000000000000000"
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
