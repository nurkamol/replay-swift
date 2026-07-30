# The `replay` command-line reader, installable with Homebrew.
#
# **This is the half of distribution that needs no certificate.** Gatekeeper's signing
# requirement is about *applications* downloaded from the internet; a command-line binary
# Homebrew builds on your own machine was never downloaded and is never quarantined. So the
# CLI can be handed to somebody today, while the app waits on a Developer ID.
#
# Installing, until there is a tagged release:
#
#   brew install --HEAD --formula ./Formula/replay.rb
#
# It is HEAD-only on purpose. A formula needs a versioned tarball and a checksum, and there
# is no tag yet — writing a `url` that 404s to look finished would be worse than saying so.
# The stable stanza below goes in with the first tag, and `.github/workflows/release.yml`
# produces exactly what it wants.
class Replay < Formula
  desc "Your own local timeline of the apps you use, from a shell"
  homepage "https://github.com/nurkamol/replay-swift"
  url "https://github.com/nurkamol/replay-swift/archive/refs/tags/v0.9.8.tar.gz"
  sha256 "86f9cd701d093cea413554b0064ee22a51c1d2e7108d525f7b877da8f1326d5e"
  license "MIT"
  head "https://github.com/nurkamol/replay-swift.git", branch: "main"

  # macOS 14. Two APIs in the *interface* begin later — `glassEffect` at 26 and
  # `Color.mix(with:by:)` at 15 — and both are guarded. The CLI touches neither.
  #
  # **No `depends_on xcode: :build`, and that was measured.** It used to be here, on the
  # assumption that the CLI shares a `Package.swift` with the app and so shares its needs. It
  # does not: `swift build --product replay` completes with Command Line Tools alone, because
  # this product is `ReplayCore` and Foundation and nothing else. The app needs Xcode for
  # SwiftUI's macro plugins; a shell tool that reads SQLite does not, and asking somebody to
  # install 15 GB of Xcode to get one was a requirement nobody had checked.
  depends_on macos: :sonoma

  def install
    # `--disable-sandbox` because SwiftPM's own sandbox and Homebrew's do not compose, and
    # this package has no dependencies to fetch — there is nothing for it to guard against.
    system "swift", "build", "--disable-sandbox", "-c", "release", "--product", "replay"
    bin.install ".build/release/replay"
  end

  test do
    # Two assertions rather than one. The first proves the binary runs at all; the second
    # proves it answers sensibly with no database, which is the state every fresh machine
    # is in and the one most likely to crash a tool that assumes its data exists.
    assert_match "replay", shell_output("#{bin}/replay --version")
    assert_match "has Replay ever run",
                 shell_output("#{bin}/replay today --database /nonexistent/activity.db 2>&1", 2)
  end
end
