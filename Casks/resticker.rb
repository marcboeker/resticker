cask "resticker" do
  version "0.7.0"

  on_arm do
    sha256 "15eaba71c3bcfc82bf581ed81a1878649e3adcefebd0d8bfbded72dd3da40675"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "3c9e328cb8bc66fc1aab2aac3bd58650d5e214d83b2da6dfa3611ba96134f5c5"
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
