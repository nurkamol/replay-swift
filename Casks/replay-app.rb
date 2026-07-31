# The Replay application, prebuilt — the fast way in.
#
# `brew trust --tap nurkamol/tap`
# `brew install --cask nurkamol/tap/replay-app`
#
# **This file is the source; nurkamol/homebrew-tap is a mirror of it.** The release workflow
# copies it over wholesale and substitutes the two generated lines, so edit it here and it
# reaches people on the next release. It used to be pasted across by hand, which meant a fix
# written here reached nobody until somebody remembered.
#
# **`brew trust` is not optional any more.** Homebrew 6 refuses to load a third-party tap
# until it has been trusted, and the failure reads like a broken tap rather than a consent
# prompt. It is the first line of every install instruction now, here and in the README.
#
# **What this trades, stated plainly.** A cask downloads a binary; a formula compiles one.
# Homebrew quarantines every cask download by default (`Cask::Installer`, `quarantine: true`),
# and macOS refuses to open a quarantined app that is not notarised by Apple. Replay carries a
# stable self-signed certificate, not a Developer ID, so the first launch would show *"Apple
# could not verify Replay is free of malware"*. The `postflight` below clears the flag so that
# does not happen — see the note on it, which is the one decision here worth arguing about.
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
# All of this goes away the day this is notarised, at which point the cask simply opens.
cask "replay-app" do
  # Bumped automatically by the release workflow's "Update the Homebrew cask" step, which
  # shas the artefact it just built. It used to be edited by hand, and 0.9.8 briefly shipped
  # with 0.9.7's checksum against a 0.9.8 URL — an install that could only fail. A number
  # copied by a person between two repositories is a number that will eventually be wrong.
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

  # **Quit Replay before Homebrew replaces the bundle.** Without this, `brew upgrade --cask`
  # swaps the application directory out from under a running process — and this particular
  # process holds an open SQLite handle it writes to every few seconds. A launcher survives
  # that; a recorder can lose the tail of the day, and the record is the entire product with
  # no cloud copy to restore from.
  #
  # Homebrew reopens it afterwards on its own (`Cask::Upgrade.reopen_apps_after_upgrade`
  # reads exactly this stanza), so an upgrade ends with Replay running again.
  uninstall quit: "app.replay.native"

  # **This is the one line here that removes a macOS security check, so it says so.**
  #
  # Homebrew tags the download as a web download; macOS then refuses to launch it because the
  # signature is self-signed rather than notarised. Stripping the flag skips that check. What
  # replaces it is the `sha256` above — a real integrity check, but one written in a
  # repository controlled by the same person who wrote the app, rather than by Apple. The
  # honest summary is that the trust collapses to "you trust nurkamol/tap", which is precisely
  # what `brew trust --tap` made you say out loud before any of this ran.
  #
  # Two things this deliberately does *not* do. It does not touch anything outside the app it
  # just installed, and it does not run on the source formula, which is never quarantined in
  # the first place. Anyone who would rather macOS kept checking can have that today:
  # `brew install --cask --no-quarantine=false` is not a thing, so the answer is the source
  # build, or deleting this block from a local copy of the tap.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Replay.app"]
  end

  # `zap` and not `uninstall`: removing an app should not remove somebody's history unless
  # they ask for it. `brew uninstall --cask replay-app` leaves the record where it is, and
  # `brew uninstall --zap` is the one that says "and the data too" out loud.
  #
  # The record is the product here — years of it, and there is no cloud copy to restore from.
  zap trash: [
    "~/Library/Application Support/app.replay.native",
    "~/Library/Caches/app.replay.native",
    "~/Library/Preferences/app.replay.native.plist",
    "~/Library/Saved Application State/app.replay.native.savedState",
  ]

  caveats <<~EOS
    Replay is not notarised by Apple, so macOS would normally refuse to open it the first
    time. This tap clears the quarantine flag on install and on every upgrade, so you should
    not see that warning at all.

    What that means, plainly: macOS did not check this app for you. What checked it was
    Homebrew, against the SHA-256 in this cask — an integrity check, but one published by
    the same project that publishes the app.

    If you would rather macOS did the checking, build from source instead. That copy is
    compiled on your Mac, never downloaded, and never quarantined:
      brew install nurkamol/tap/replay-app-source

    Replay records with no permissions at all — no Accessibility, no Automation, no Screen
    Recording — and keeps everything in one local SQLite file.

    Uninstalling leaves that file alone. `--zap` is the one that deletes your record too.
  EOS
end
