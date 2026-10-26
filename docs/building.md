<p align="center"><img src="../art/tug-head.png" width="96" alt="Tug"></p>

<h1 align="center">Building sheepdog</h1>

sheepdog builds with Swift Package Manager and a Makefile. It needs macOS 14 or later and Xcode
16 or later.

## Build and run

```sh
make run
```

`make run` builds `.build/Sheepdog.app`, signs it for this Mac, and opens it. `make app` builds
the app without opening it.

## Release builds

```sh
make zip ARCHS="arm64 x86_64"
make dmg
```

`make zip` builds a universal app for Apple silicon and Intel and zips it to
`.build/Sheepdog.zip`. `make dmg` packages the app already built in `.build/Sheepdog.app` into
`.build/Sheepdog.dmg`, with the window layout and background from `dmg.py`. It needs
[dmgbuild](https://pypi.org/project/dmgbuild/), installed with `pip install dmgbuild`. Both
targets sign ad hoc for this Mac unless `SIGN_ID` names a real signing identity.

Before tagging, set `CFBundleShortVersionString` and `CFBundleVersion` in
`Sources/Sheepdog/Info.plist` to the new version. Publishing a GitHub release then runs the
release workflow, which:

- Fails unless both versions match the tag, then runs the tests.
- Builds the universal app signed with the Developer ID certificate, notarizes it and staples the
  ticket.
- Builds the disk image, signs and notarizes it, and staples its ticket.
- Checks the zip, the disk image and the app on it with `stapler` and `spctl`, as a user's Mac
  would.
- Attaches the zip and disk image under versioned names, such as
  `sheepdog_v1.5.2_macos_universal.dmg`, and under fixed names, such as
  `sheepdog_macos_universal.dmg`, so `releases/latest/download/` links always fetch the newest.
  `SHA256SUMS` lists every file's hash, and each one carries a GitHub build provenance
  attestation.
- Writes the new cask into `dcadolph/homebrew-tap`, then installs it from the tap on a clean Mac
  runner and audits it.

The workflow stops when any signing secret is unset: `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`,
`NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`. The tap step needs
`HOMEBREW_TAP_TOKEN`. The release reads the direct sign-in client IDs from the repository
secrets `SHEEPDOG_MICROSOFT_CLIENT_ID`, `SHEEPDOG_GOOGLE_CLIENT_ID` and
`SHEEPDOG_GOOGLE_CLIENT_SECRET`, and ships without direct sign-in while they are unset. The
repository variable `SHEEPDOG_SUPPORT_URL` sets the support link in Tug's menu and settings,
and the app shows none while it is unset.

## Direct Microsoft and Google sign-in

By default sheepdog reads calendars through macOS Calendar and needs no account of its own.
Signing in to Microsoft or Google directly needs your own app registration. Pass the client IDs
to the build:

```sh
make app SHEEPDOG_MICROSOFT_CLIENT_ID=... SHEEPDOG_GOOGLE_CLIENT_ID=... SHEEPDOG_GOOGLE_CLIENT_SECRET=...
```

Tokens are kept in the macOS Keychain.

## Tests

```sh
make test
```

## Demo GIF and screenshots

```sh
make demo
```

`make demo` redraws `art/demo.gif` and the stills used in these docs. It needs ffmpeg. The app
draws every frame itself from its real alert views over a made-up desktop, so no real screen,
calendar or account is ever captured.
