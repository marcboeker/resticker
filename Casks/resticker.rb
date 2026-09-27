cask "resticker" do
  version "0.1.1"
  sha256 "542e20b7b8e9a70dd386e911d7e2bf04d5536d9c38646ea85f6b1b8f5f2777df"

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

  zap trash: "~/.config/resticker"
end
