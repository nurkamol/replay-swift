# The Replay application, prebuilt — the fast way in.
#
# `brew install --cask nurkamol/tap/replay-app`
#
# **What this trades, stated plainly.** A cask downloads a binary; a formula compiles one.
# Homebrew quarantines every cask download by default (`Cask::Installer`, `quarantine: true`),
# and macOS refuses to open a quarantined app that is not notarised by Apple. Replay is signed
# ad-hoc, not with a Developer ID, so the first launch shows *"Apple could not verify Replay
# is free of malware"* and needs one trip through System Settings. The caveats below say so,
# and so does the README — nobody should meet that dialog as a surprise.
#
# In exchange it installs in seconds, needs no Xcode, and lands in /Applications.
#
# The alternative is still here: `brew install nurkamol/tap/replay-app-source` builds from
# source, is never downloaded, and therefore opens with no warning at all — at the cost of a
# full Xcode and a couple of minutes.
#
# **This token belongs to the cask, and that was learned the hard way.** The source formula
# used to be called `replay-app` too, on the reasoning that one name for one product is
# clearer and `--cask` would choose the delivery. Homebrew resolves a shared token to the
# formula, so the first person to type `brew install nurkamol/tap/replay-app` got the source
# build and an error about needing a 15 GB Xcode. The formula is `replay-app-source` now and
# the plain command does the fast, obvious thing.
#
# Both go away the day this is notarised, at which point the cask simply opens.
cask "replay-app" do
  version "0.9.8"
  sha256 "09f9f8825c74beeef01e88ca8f6da0c1af910bd5ad1541fb27ec69679ec86366"

  url "https://github.com/nurkamol/replay-swift/releases/download/v#{version}/Replay-#{version}.zip",
      verified: "github.com/nurkamol/replay-swift/"
  name "Replay"
  desc "Private, local timeline of the apps you use"
  homepage "https://github.com/nurkamol/replay-swift"

  # macOS 14 as of 0.9.8. The two interface APIs that begin later are guarded; see
  # docs/FINDINGS.md and the CHANGELOG entry for how that floor was measured.
  depends_on macos: :sonoma

  app "Replay.app"

  # `zap` and not `uninstall`: removing an app should not remove somebody's history unless
  # they ask for it. `brew uninstall --cask replay-app` leaves the record where it is, and
  # `brew uninstall --zap` is the one that says "and the data too" out loud.
  #
  # The record is the product here — years of it, and there is no cloud copy to restore from.
  zap trash: [
    "~/Library/Application Support/app.replay.native",
    "~/Library/Caches/app.replay.native",
    "~/Library/Preferences/app.replay.native.plist",
  ]

  caveats <<~EOS
    Replay is not signed with an Apple Developer ID, so macOS will refuse to open it the
    first time and offer only "Move to Trash".

    To open it:
      1. Try to open Replay once, and dismiss the warning.
      2. System Settings > Privacy & Security, scroll down, click "Open Anyway".
      3. Confirm. It opens normally from then on.

    Or, in one line:
      xattr -dr com.apple.quarantine /Applications/Replay.app

    Ignore any advice to "right-click and choose Open" — Apple removed that in macOS 15.

    The warning is about a missing certificate, not about anything found in the app. To skip
    it entirely, build from source instead — that copy is never downloaded and so is never
    quarantined:
      brew install nurkamol/tap/replay-app-source
  EOS
end
