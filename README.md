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

Eighteen collars in Settings, Look: Jax, BlackDiamond, GoldenSpark, Rubie, Lightning, Thunder,
StrawHat, Bubblegum, Berserker, PickleJuice, Trunk, MintChip, Rose, FogDog, VolcanoTaffy,
Gambit, PaleNimbus and DangerRoom. Each one colors the collar, the
alarm, the countdown pill and the hand-back card, and every one is checked for contrast. Pick **Custom** to choose your
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
pill, the hand-back card and Settings. The menu bar keeps plain Tug. Outfits start off. Turn on
**Dress Tug up for holidays** in Settings, Look, or on the setup window's dress-up step.

In the same days the alarm barks a holiday tune instead of the plain bark: Auld Lang Syne, Let Me
Call You Sweetheart, The Irish Washerwoman, In the Hall of the Mountain King, Over the River and
Through the Wood, and Jingle Bells. Easter has no tune. Every note is Tug's own woof. The tune plays
only when the alarm sound is one of Tug's, and the warning chime stays a single woof. Tunes start
off too. Turn on **Bark holiday tunes** in Settings, Sound, or on the same setup step.

## Tug in the menu bar

When Tug naps he lies down and settles with his chin on his paws, and now and then he looks up.
Wake him and he hops up, wags and barks twice. He barks when Sheepdog opens, and on **Quit
Sheepdog** he drops into a play bow and leaps out of the menu bar. Reduce Motion keeps him still.

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

The app is signed and notarized, so it opens like any other Mac app. The first launch walks
through calendar access, connecting calendars, when Tug barks and whether he dresses up, and
**Set up Sheepdog…** in the menu reopens it. If your company blocks direct sign-in, add the work account in System Settings,
Internet Accounts, and Sheepdog reads it through macOS Calendar. Homebrew users can run `brew install --cask dcadolph/tap/sheepdog` instead.

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

Every six hours Sheepdog asks GitHub for the latest release, and the check sends no version or
identifier. The first check waits a minute after launch. When a newer release is out and
**Install updates automatically** is on, Sheepdog downloads the release zip and its `SHA256SUMS`
file from GitHub's release files and checks the zip's hash. It unpacks the zip and checks that the
app inside carries a valid Apple Developer ID signature from team `U7L4P2YHWJ`, matches the
running app's signing requirement, is notarized by Apple, and is the expected newer version for
this macOS. Any failed check stops the update and names the step.

It installs at a quiet moment. That means never during an alarm, a call, off hours, a meeting
under way or within 15 minutes of the next meeting, or while a Sheepdog window is open, and only
after 30 seconds without keyboard or mouse input. Then it swaps the app in Applications and
starts again. If it finds no quiet moment before you quit, it installs on the next launch. If the
new version does not start, Sheepdog puts the previous version back, never tries that version
again, and a card says so.

Settings, General has two switches, **Check for updates** and **Install updates automatically**,
both on by default. With installs off, Tug's menu shows "Sheepdog X is available" and opens the
release page. **Check for Updates…** in Tug's menu checks at once, and **Update Now** there
installs right away without waiting for a quiet moment. It installs only when Sheepdog runs from
Applications. Otherwise the button is **View Release**. After an update a card says what
changed. Homebrew still installs it with `brew install --cask dcadolph/tap/sheepdog`. The cask
is marked `auto_updates`, so `brew upgrade` leaves Sheepdog to update itself, and
`brew upgrade --greedy --cask sheepdog` forces it.

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
- [For IT admins](https://macsheepdog.com/admins) explains the Microsoft permissions an admin approves.

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
