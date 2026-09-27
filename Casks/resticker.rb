cask "resticker" do
  version "0.2.0"
  sha256 "a2fc8f3529adfb02c8d78e889efcb65160f760086b9f3635add7c1bce0c47085"

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
