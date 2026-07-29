# The Replay *application*, built on your own machine — the quiet way in.
#
# `brew install nurkamol/tap/replay-app-source`
#
# **Named `-source` because the default has to be the fast one.** This was `replay-app`, the
# same token as the cask, on the reasoning that one name for one product is clearer and the
# `--cask` flag would choose the delivery. That was wrong the first time somebody typed it:
# Homebrew resolves a shared token to the *formula*, so `brew install nurkamol/tap/replay-app`
# silently picked this, and this needs a full 15 GB Xcode. The person got an error instead of
# an app. A default that fails for most people is not a default.
#
# Now the plain command installs the cask, and this is the deliberate opt-in it should always
# have been.
#
# **It is how the app is shared without a Developer ID, and it is not a workaround.**
# Gatekeeper's signing requirement applies to applications *downloaded* from the internet:
# the quarantine flag is set by the browser that fetched the file. An app Homebrew compiles
# here was never downloaded, carries no quarantine flag, and opens with no dialog — the same
# reason `./scripts/make-app.sh` produces something that just runs.
#
# So a cask would need a certificate and this does not. A cask installs a prebuilt binary
# from a release page; a formula builds from source. That difference is the whole trick.
#
#   brew install --HEAD nurkamol/tap/replay-app-source
#
# Homebrew normally prefers casks for GUI applications, and it is right to — but a cask
# cannot build, and building is precisely what makes this openable.
class ReplayAppSource < Formula
  desc "Private, local timeline of the apps you use — the macOS application"
  homepage "https://github.com/nurkamol/replay-swift"
  url "https://github.com/nurkamol/replay-swift/archive/refs/tags/v0.9.8.tar.gz"
  sha256 "78f1bf9e1f21bd137cb8fc73872c417cb39d33d2953ce98bb10a97ae47be0f96"
  license "MIT"
  head "https://github.com/nurkamol/replay-swift.git", branch: "main"

  # macOS 14 since 0.9.8. The two interface APIs that begin later — `glassEffect` (26) and
  # `Color.mix(with:by:)` (15) — are guarded, and below 26 the Surfaces setting offers the
  # two styles that exist. Measured by building against each floor, not assumed.
  #
  # **Xcode, and not Command Line Tools — the reason is SwiftUI's macros.** `@State`, `@Entry`
  # and `#Preview` are macros whose implementations (`SwiftUIMacros`, `PreviewsMacros`) ship
  # inside Xcode; CLT carries the compiler but not the plugins, so a build there fails with
  # "external macro implementation type could not be found" on the first view. It is not the
  # App Intents processor, which is optional and skipped when absent. Measured 2026-07-30 by
  # building the package with `DEVELOPER_DIR` pointed at CLT: the CLI succeeded, the app did
  # not. The `replay` formula therefore does *not* require Xcode; this one does.
  depends_on xcode: :build
  depends_on macos: :sonoma

  def install
    # `--disable-sandbox` as an argument, not an environment variable: Homebrew scrubs the
    # environment it hands a build, so the first version of this silently did nothing and
    # SwiftPM tried to sandbox inside Homebrew's sandbox — `sandbox_apply: Operation not
    # permitted`. The package fetches no dependencies, so there is nothing to guard against.
    system "./scripts/make-app.sh", "release", "--disable-sandbox"
    prefix.install "build/Replay.app"
    # A launcher, so `replay-app` opens it from a shell without anyone hunting for the
    # bundle inside the Cellar.
    (bin/"replay-app").write <<~SH
      #!/bin/sh
      exec open -a "#{prefix}/Replay.app" "$@"
    SH
    chmod 0755, bin/"replay-app"
  end

  def caveats
    <<~EOS
      Replay.app is in the Cellar rather than /Applications, because Homebrew does not
      move application bundles around. Link it once and Spotlight and the Dock will find it:

        ln -sfn #{opt_prefix}/Replay.app /Applications/Replay.app

      It opens with no security warning: it was built here rather than downloaded, so macOS
      never marked it as quarantined. A signed disk image is coming; this needs no
      certificate and never will.
    EOS
  end

  test do
    # The bundle is complete and says who it is — the two things that decide whether macOS
    # will launch it at all.
    assert_path_exists prefix/"Replay.app/Contents/MacOS/Replay"
    assert_match "app.replay.native",
                 shell_output("/usr/bin/plutil -p '#{prefix}/Replay.app/Contents/Info.plist'")
    # And it is signed, even if only ad-hoc. An unsigned bundle will not launch on Apple
    # silicon at all, which is a failure worth catching here rather than on someone's Mac.
    system "/usr/bin/codesign", "--verify", "--deep", prefix/"Replay.app"
  end
end
