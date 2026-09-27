cask "resticker" do
  version "0.4.1"

  on_arm do
    sha256 "7cc3292eafc1a00d90e2d9f46e9781ee1085894c56be4b7dc3836f607bf7d844"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "bf51bbd4c86648e1dade160c4d5186170e5780f8b70eb0b8f71bdd952e207e91"
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

  zap trash: [
    "~/Library/Application Support/Resticker",
    "~/Library/Preferences/net.at6.resticker.plist",
  ]
end
