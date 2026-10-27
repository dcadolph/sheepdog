<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="art/banner.png">
    <img src="art/banner-light.png" width="100%" alt="Tug, a border collie, barking">
  </picture>
</p>

<h1 align="center">sheepdog</h1>

<p align="center">
  <a href="https://macsheepdog.com"><img src="https://img.shields.io/badge/macsheepdog.com-Download_for_Mac-3d7ea6?style=for-the-badge&logo=apple&logoColor=white" alt="macsheepdog.com: Download for Mac"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="Apache 2.0 license">
</p>

<p align="center"><strong>The meeting alarm that barks.</strong></p>

<p align="center"><img src="art/demo.gif" width="720" alt="The countdown pill, the full-screen alarm with a snooze, Hold my place with a typed note, Join from the pill, and the note handed back after the meeting"></p>

Calendar notifications are easy to dismiss without reading. When you are deep in something, a
banner in the corner does not register, and ten minutes later you are late. sheepdog gets louder
as the meeting gets closer. First a chime and a small countdown, then a full-screen alarm with
Tug barking until you join, snooze or skip. It also holds a note on what you were doing and
hands it back when the meeting ends.

## Hold my place

<p align="center"><img src="art/handback.png" width="440" alt="The hand-back card: Before Design review you were: Retry tests for the upload queue, with Copy, Done, and Clear all"></p>

A calendar alert tells you where to be. It does not remember what you were doing when it went
off, and that is the part that costs you ten minutes after the call. When the warning chime
sounds, type one line about what you were in the middle of, right in the countdown pill. The
note never takes keyboard focus on its own, so it cannot swallow the sentence you are typing
somewhere else. When the meeting ends, a card in the top right corner hands the note back with
**Copy** and **Done**. If you are still on the call, it waits for your mic to go quiet first.

Notes stay on your Mac, and unclaimed ones are cleared at 4 a.m.

sheepdog is free and will stay free. If I ever stop maintaining it, I'll archive it, and the code
stays open.

## Tug's collar

Ten collars in Settings, Look: Wolf, Black Diamond, Golden Spark, Rubie, Lightning, Thunder,
Strawhat, Grapes, Bubblegum and Berserker. Each one colors the collar, the alarm, the countdown
pill and the hand-back card, and every one is checked for contrast. Pick **Custom** to choose your
own: a background and a ring and buttons color are required, the collar and the already-started
color are optional. Tug works out the text, surface and muted colors so everything stays readable,
and if a color you picked would not read, he moves it a little and says so under the picker.
**Start from** copies any collar's colors into Custom as a starting point. The color panel takes a
hex value or a drag around the wheel.

## Holiday outfits

Tug dresses up in the days around seven holidays: a party hat for New Year's (Dec 27 to Jan 2), a
heart headband for Valentine's Day (Feb 10 to 14), a green top hat for St. Patrick's Day (Mar 13 to
17), bunny ears for Easter (the Saturday before through the Tuesday after), a vampire cape for
Halloween (Oct 24 to 31), a turkey hat for Thanksgiving week (Monday to Sunday), and a Santa hat for
Christmas (Dec 18 to 26). The outfit goes over any collar and shows on the alarm, the countdown
pill, the hand-back card, Settings and the menu bar. Turn off **Dress Tug up for holidays** in
Settings, Look, to keep him plain.

In the same days the alarm barks a holiday tune instead of the plain bark: Auld Lang Syne, Let Me
Call You Sweetheart, The Irish Washerwoman, In the Hall of the Mountain King, Over the River and
Through the Wood, and Jingle Bells. Easter has no tune. Every note is Tug's own woof. The tune plays
only when the alarm sound is one of Tug's, and the warning chime stays a single woof. Turn off
**Bark holiday tunes** in Settings, Sound, to keep the plain bark.

## Requirements

- macOS 14 or later
- Xcode 16 or later, only to build from source

## Download

Download `sheepdog_vX.Y.Z_macos_universal.dmg` from the
[latest release](https://github.com/dcadolph/sheepdog/releases/latest), open it, and
double-click Sheepdog. After one okay it copies itself into Applications, starts from there,
ejects the disk image, and moves it to the Trash. Dragging Sheepdog onto Applications works too,
and then it asks once before trashing the disk image. The zip is still attached for scripts and
Homebrew. It runs on Apple silicon and Intel Macs.

The app is signed and notarized, so it opens like any other Mac app. Allow calendar access
when macOS asks. Homebrew users can run `brew install --cask dcadolph/tap/sheepdog` instead.

### Verify the download

Every release is signed with a Developer ID certificate and notarized by Apple, and the
notarization ticket is stapled to the app. Each release also lists a SHA-256 hash for each zip
and disk image in `SHA256SUMS`, and each one carries a GitHub build provenance attestation. To
check a download, run these from the folder that holds the files:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
gh attestation verify sheepdog_macos_universal.dmg --repo dcadolph/sheepdog
gh attestation verify sheepdog_macos_universal.zip --repo dcadolph/sheepdog
unzip sheepdog_macos_universal.zip
spctl -a -vv Sheepdog.app
codesign -dv Sheepdog.app 2>&1 | grep TeamIdentifier
```

`spctl` should print `accepted` with `source=Notarized Developer ID`, and the team identifier
should be `U7L4P2YHWJ`.

Once a day Sheepdog asks GitHub for the latest release. When a newer one exists, the menu shows
a line that opens its release page, and a card offers **Update now**, **Remind me later** and
**Skip this version**. The card never shows during a countdown, a call or off hours. Update now
appears only when Sheepdog runs from Applications. For a Homebrew install it runs `brew update`
and then `brew upgrade --cask sheepdog` in the background, logging to
`~/Library/Caches/com.dcadolph.sheepdog/sheepdog-update.log`. If Homebrew does not know of the
release yet, it stops with "Homebrew has no newer Sheepdog yet." in that log, Sheepdog keeps
running, and the button turns into **Open release page**. Otherwise it downloads the release's
disk image, checks that the app on it is signed by team `U7L4P2YHWJ`, and installs it. Nothing
installs until you press it, and the check sends no version or identifier. Turn it off in
settings with **Check for updates**. To check right away, pick **Check for Updates…** in Tug's
menu.

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

- [How To](https://macsheepdog.com/how-to) has short guides with steps and answers to common
  questions, from connecting calendars to moving your settings to another Mac.
- [Using sheepdog](docs/using.md) covers the countdown pill, the alarm, Hold my place, working
  hours, installing and updating, and every setting.
- [Building sheepdog](docs/building.md) covers direct Microsoft and Google sign-in, the tests and
  the demo renderer.

## Credits

Tug's bark is cut from [Ladrido perro](https://commons.wikimedia.org/wiki/File:Ladrido_perro.ogg)
by Edo.pt2 on Wikimedia Commons, released under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

The holiday tunes are that same bark, pitched to each note. The melodies are in the public domain
and the arrangements were written for sheepdog:

- Auld Lang Syne, traditional Scots air, 1799.
- Let Me Call You Sweetheart, Leo Friedman, 1910.
- The Irish Washerwoman, traditional jig, in print by 1790.
- In the Hall of the Mountain King, Edvard Grieg, 1875.
- Over the River and Through the Wood, traditional tune to Lydia Maria Child's 1844 poem.
- Jingle Bells, James Lord Pierpont, 1857.

## License

[Apache 2.0](LICENSE)
