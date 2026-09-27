# Other Install Options

The main [README](../README.md) covers installing via Homebrew. Two other ways to get
Resticker:

## Download a release

Grab the latest release from the
[Releases page](https://github.com/marcboeker/resticker/releases): `Resticker-macos-arm64.zip`
for Apple Silicon Macs, or `Resticker-macos-amd64.zip` for Intel Macs. Unzip it, and move
`Resticker.app` to `~/Applications`. Then open it:

```sh
open ~/Applications/Resticker.app
```

The app is ad-hoc signed, so macOS Gatekeeper will refuse to open it with a normal
double-click the first time. Either right-click the app and choose **Open**, or clear
the quarantine flag yourself:

```sh
xattr -dr com.apple.quarantine ~/Applications/Resticker.app
```

## Build it yourself

Clone this repository, then build and install the app:

```sh
git clone https://github.com/marcboeker/resticker.git
cd resticker
make install
open ~/Applications/Resticker.app
```

`make install` builds the app and copies it to `~/Applications`. See
[DEVELOPMENT.md](DEVELOPMENT.md) for the other make targets, and
[SIGNING.md](SIGNING.md) if you'd rather sign with a stable identity than re-approve a
keychain prompt after every rebuild.
