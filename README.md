<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="art/banner.png">
    <img src="art/banner-light.png" width="100%" alt="Tug, a border collie, barking">
  </picture>
</p>

<h1 align="center">Sheepdog</h1>

<p align="center">
  A free macOS menu bar meeting alarm for people who lose track of time.<br>
  Tug, the border collie, herds you into your meetings.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license">
</p>

<p align="center"><img src="art/demo.gif" width="720" alt="The countdown pill, then the full-screen alarm with Snooze and Join"></p>

Calendar notifications are easy to dismiss without reading. When you are deep in something, a
banner in the corner does not register, and ten minutes later you are late. Sheepdog gets louder
as the meeting gets closer. First a chime and a small countdown, then a full-screen alarm with
Tug barking until you join, snooze or skip. It also holds a note on what you were doing and
hands it back when the meeting ends.

## Requirements

- macOS 14 or later
- Xcode 16 or later, only to build from source

## Download

Grab `sheepdog_<version>_macos_universal.zip` from the
[latest release](https://github.com/dcadolph/sheepdog/releases/latest), unzip it, and move
`Sheepdog.app` to `/Applications`. It runs on Apple silicon and Intel Macs.

The app is not notarized yet, so macOS blocks the first launch. Open it once, then go to
**System Settings > Privacy & Security** and click **Open Anyway** next to the Sheepdog
message. Allow calendar access when macOS asks.

## Build from source

```sh
git clone https://github.com/dcadolph/sheepdog.git
cd sheepdog
make run
```

`make run` builds `.build/Sheepdog.app`, signs it for this Mac, and opens it. Allow calendar
access when macOS asks, then pick **Test the alarm** from Tug's menu to see the whole thing
without a real meeting. Copy the app to `/Applications` to keep it.

## Docs

- [Using Sheepdog](docs/using.md) covers the countdown pill, the alarm, Hold my place and every
  setting.
- [Building Sheepdog](docs/building.md) covers direct Microsoft and Google sign-in, the tests and
  the demo renderer.

## Credits

Tug's bark is cut from [Ladrido perro](https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg)
by Edo.pt2 on Wikimedia Commons, released under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## License

[Apache 2.0](LICENSE)
