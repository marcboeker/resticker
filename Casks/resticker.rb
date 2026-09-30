cask "resticker" do
  version "0.5.1"

  on_arm do
    sha256 "1270c5edc52cf04a8e174f441aa190d4da440e7577e7cae835596958986ad616"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "62e0a5a5200788e320d66afde974b6f6d0fa6654bbbaaa74ef60d9b3c0960b04"
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
