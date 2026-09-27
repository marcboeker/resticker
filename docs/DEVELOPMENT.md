# Development

Reference for the Makefile targets used to build, test, and install
Resticker from source. See [INSTALL.md](INSTALL.md#build-it-yourself)
for the minimal steps to build and run the app.

## Make targets

| Target | Action |
| --- | --- |
| `make build` / `make test` | Build or run the unit tests without installing. |
| `make run` | Install and launch in one step. |
| `make install` | Build, ad-hoc sign, and copy the app to `~/Applications`. |
| `make uninstall` | Removes the app. Leaves your settings and keychain items in place. |
| `make clean` | Removes build output. |

By default, `make install` ad-hoc signs the app, which forces a fresh
keychain prompt on every rebuild. See [SIGNING.md](SIGNING.md) to set a
stable `CODESIGN_IDENTITY` and avoid that.

To cross-build for the other architecture, pass `ARCH=x86_64` or `ARCH=arm64`
to `make build`/`make bundle`, e.g. `make bundle ARCH=x86_64`. This builds
into an arch-specific `.build-<arch>` and `dist/<arch>` so it doesn't clobber
a native build. Leave `ARCH` unset for the normal native build used by
`make install`/`make run`.

## Resetting for testing

Resticker stores its settings in UserDefaults, and the repository password
and environment variables in the Keychain, under the service `resticker`. To
test the app as if freshly installed, clear both.

Find the bundle identifier in [Resources/Info.plist](../Resources/Info.plist)
(`net.at6.resticker`), then remove its UserDefaults:

```sh
defaults delete net.at6.resticker
```

Remove the Keychain items:

```sh
security delete-generic-password -s resticker -a repository-password
security delete-generic-password -s resticker -a environment-variables
```
