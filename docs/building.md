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
```

`make zip` builds a universal app for Apple silicon and Intel and zips it to
`.build/Sheepdog.zip`. Publishing a GitHub release runs the same build and attaches the zip and
its SHA256SUMS to the release. The release reads the direct sign-in client IDs from the
repository secrets `SHEEPDOG_MICROSOFT_CLIENT_ID`, `SHEEPDOG_GOOGLE_CLIENT_ID` and
`SHEEPDOG_GOOGLE_CLIENT_SECRET`, and ships without direct sign-in while they are unset.

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
