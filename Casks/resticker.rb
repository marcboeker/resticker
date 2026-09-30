cask "resticker" do
  version "0.6.0"

  on_arm do
    sha256 "9da1f6845170515b72a6a7c55cd7e05e39b0383d647eb591542c9c548c6fedfd"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "b0b89005762a0440563ad02da70e5602d27999eaf27e1a012105f807e33e8729"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-amd64.zip"
  end

  name "Resticker"
  desc "Menu bar app that runs restic backups on a schedule"
  homepage "https://github.com/marcboeker/resticker"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Resticker.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Resticker.app"]
  end

  # Quit the running app before Homebrew replaces the bundle on upgrade/uninstall — otherwise
  # the update clobbers a live process.
  uninstall quit: "one.m8n.resticker"

  zap trash: [
    "~/Library/Application Support/Resticker",
    "~/Library/Preferences/one.m8n.resticker.plist",
  ]
end
