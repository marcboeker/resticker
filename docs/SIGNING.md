# Signing the app locally

`make install` ad-hoc signs the app by default. An ad-hoc signature has no
stable identity, so it changes on every build. macOS ties keychain access to
the exact signature that created an item, so after each `make install` you
are asked to confirm access to your stored repository password again.

To keep a stable signature across rebuilds, and stop the repeated keychain
prompt, sign with your own identity instead of ad-hoc:

1. List the codesigning identities in your keychain:

   ```sh
   security find-identity -v -p codesigning
   ```

   If you don't have one, open **Keychain Access** and create a self-signed
   certificate (**Certificate Assistant → Create a Certificate…**, type
   **Code Signing**). An Apple Developer account also works, if you have one.

2. Copy `.env.example` to `.env` and set `CODESIGN_IDENTITY` to that
   identity's name:

   ```sh
   cp .env.example .env
   ```

   ```
   CODESIGN_IDENTITY=Apple Development: you@example.com (TEAMID)
   ```

   If multiple identities share the same name, use the SHA-1 hash shown by
   `security find-identity` instead, to pin the exact one.

3. Run `make install` as usual. The Makefile reads `.env` automatically, so
   the signature stays the same on every rebuild and macOS stops asking for
   your keychain password.

`.env` is gitignored, so your identity stays local. You can still override it
for a single build without touching `.env`:

```sh
make install CODESIGN_IDENTITY="..."
```
