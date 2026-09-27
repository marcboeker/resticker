cask "resticker" do
  version "0.3.0"
  sha256 "acce4ff397780e24aaff07b0204794be736a2599e8cf803ef27f52f7c89fee53"

  url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
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
