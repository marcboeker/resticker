cask "resticker" do
  version "0.5.0"

  on_arm do
    sha256 "96d9c4127608f6050946524c2fa77eb4f273efe1d286b48e8447849306efde7d"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "16c77272f9ca3dfb36d0bf428d6fd3e823b7f8640d94f945f4c5870b2c4f841d"
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
  uninstall quit: "net.at6.resticker"

  zap trash: [
    "~/Library/Application Support/Resticker",
    "~/Library/Preferences/net.at6.resticker.plist",
  ]
end
