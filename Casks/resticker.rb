cask "resticker" do
  version "0.4.0"

  on_arm do
    sha256 "274800d2be5ae8a9150518a6257d1ffad0c0525af7511f04d2b837040db9068c"
    url "https://github.com/marcboeker/resticker/releases/download/v#{version}/Resticker-macos-arm64.zip"
  end

  on_intel do
    sha256 "0000000000000000000000000000000000000000000000000000000000000000"
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
