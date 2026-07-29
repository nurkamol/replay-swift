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
# The alternative is still here and still works: `brew install nurkamol/tap/replay-app` — the
# same name without `--cask` — builds from source, is never downloaded, and therefore opens
# with no warning at all, at the cost of a full Xcode and a couple of minutes.
#
# **The shared name is deliberate.** Homebrew allows one cask and one formula to be called the
# same thing and picks the formula unless `--cask` is given. Naming this `replay` would have
# collided with the *command-line reader*, so `brew install nurkamol/tap/replay` would hand
# somebody the CLI when they meant the app. Sharing a name with the app's own source formula
# instead means the name always denotes the same product and the flag only chooses how it
# arrives.
#
# Both go away the day this is notarised, at which point the cask simply opens.
cask "replay-app" do
  version "0.9.8"
  sha256 "71a55d1ed4ce6308bdeba031df0525f1d075abed66beea65e96a53a1fea2316c"

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
    quarantined (same name, no --cask):
      brew install nurkamol/tap/replay-app
  EOS
end
