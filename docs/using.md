<p align="center"><img src="../art/tug-head.png" width="96" alt="Tug"></p>

<h1 align="center">Using sheepdog</h1>

sheepdog signs in to Microsoft and Google directly, reads every other calendar in macOS Calendar,
and escalates in three steps as each meeting gets closer. Each step is described below in the
order it happens.

## The countdown pill

<p align="center"><img src="../art/pill.png" width="600" alt="The countdown pill at the top of the screen: Tug, the meeting title, 2:05, and Join"></p>

Ten and five minutes before the start, Tug woofs once and a small pill shows the countdown at the
top of the screen. It has a Join button and stays out of the way of your work. The X hides the
pill, and the alarm still comes a minute before the start.

## The alarm

<p align="center"><img src="../art/takeover.png" width="720" alt="The full-screen alarm: Tug inside a countdown ring, the meeting title, Join now, Snooze, and Hold my place"></p>

A minute before the start, the alarm covers every display and Tug starts barking. The ring
around Tug empties as the start gets closer and turns red once the meeting has started.

- **Join now** opens the meeting link, straight into the Teams or Zoom app for those links.
  Events with no link say **I'll attend**.
- **Snooze** drops back to the countdown for a minute, or 30 seconds once the meeting has
  started. Each meeting gets two snoozes.
- **I'm skipping this one** ends the alerts for that meeting.
- The **X** stops the barking and leaves only the silent countdown pill for that meeting.
- Starting a call that uses the mic counts as joining and quiets the alarm.

When the alarm closes, focus goes back to the app you were using.

## Hold my place

<p align="center"><img src="../art/handback.png" width="440" alt="The hand-back card: Before Design review you were: Retry tests for the upload queue, with Copy, Done, and Clear all"></p>

Before the meeting, jot down what you were in the middle of, from the pill or with **Hold my
place** on the alarm. Clicking it quiets Tug while you type. When the meeting ends, a card in the
top right corner of your main display hands the note back.

- **Copy** puts the note on the clipboard. **Done** puts the card away.
- The card waits while your mic is still in use, so it shows up when the call is over.
- More than one note stacks newest first, like macOS notifications, with **Clear all**.
- Notes nobody picked up are cleared at 4 a.m.

## Let them know

Add your team's Slack channels in Settings, under Slack. Use **Copy link** on a channel in Slack
and paste it in, with a name such as #team. The alarm then shows **Let them know** next to
**Hold my place**.

- **Running late** copies "Running a few minutes late to Design review." and opens the channel.
  The alarm drops to the countdown pill, so the meeting is still tracked.
- **Can't make it** copies "I can't make Design review." and opens the channel. The meeting
  counts as skipped, the same as **I'm skipping this one**.
- With more than one channel, pick one first. Paste and press Return in Slack to send.
- sheepdog never signs in to Slack and never sends anything itself.

## Working hours

Turn on **Only bark during working hours** in Settings to keep Tug quiet in the evening or on
weekends. It starts at 8:00 to 18:00, Monday to Friday. Change the times and days to fit.

- **Outside working hours** picks what Tug does for a meeting outside your hours. **Silent** says
  nothing, like Nap time. **Quiet** shows the countdown pill with no sound and no alarm. **Full
  alarm** treats every meeting the same, as if working hours were off.
- Tug goes by when the meeting starts. With hours ending at 17:00, a 16:55 meeting alarms in full
  even if you snooze past 17:00, and a 17:05 meeting is outside your hours from start to finish.
- Meetings outside your hours stay in Tug's menu, marked "after hours". Hover over the glyph to
  see when he is back, e.g. "Off duty until Mon 8:00 AM".
- **Nap time** offers **Until work starts** instead of until morning.
- **Test the alarm** always runs the full alarm.
- Working hours are kept on this Mac only. Phone calendar apps alert on their own.

Examples:

| You want     | Start | End   | Days            |
|--------------|-------|-------|-----------------|
| Evenings off | 8:00  | 18:00 | Every day       |
| Weekends off | 0:00  | 0:00  | Monday-Friday   |
| Night shift  | 22:00 | 6:00  | Sunday-Thursday |

A start and end that match cover the whole day. An end before the start is an overnight shift,
and it belongs to the day it starts, so a Thursday 22:00 shift runs into Friday morning.

## Install and update

Open the disk image from the latest release and double-click Sheepdog. Click **Install** and it
copies itself into Applications, starts from there, ejects the disk image, and moves it to the
Trash. Dragging Sheepdog onto Applications works too, and then it asks once before moving the
disk image to the Trash. A downloaded copy started from anywhere else, such as Downloads,
offers **Move to Applications**. Homebrew users can run
`brew install --cask dcadolph/tap/sheepdog` instead.

Once a day Sheepdog asks GitHub for the latest release. When a newer one is out, Tug's menu shows
a line such as "Sheepdog 1.6.0 is available" that opens its release page, and a card in the top
right corner offers three choices.

- **Update now** installs the new version. A Homebrew install runs `brew update` and
  `brew upgrade --cask sheepdog` in the background. Any other install downloads the release's
  disk image, checks that the app on it is signed by the same developer, and installs it. Either
  way Sheepdog quits and the new version starts.
- **Remind me later** puts the card away. It comes back a week later, then every 30 days, three
  times at most.
- **Skip this version** keeps the card away until the next release. The menu line stays.

The card never shows during a countdown, the alarm, a call, a hand-back card or off hours. It
offers **Update now** only when Sheepdog runs from Applications, and **Open release page**
otherwise. If an update fails, the button turns into **Open release page** so you can download it
by hand. A Homebrew update fails when Homebrew does not know of the release yet, and the log at
`~/Library/Caches/com.dcadolph.sheepdog/sheepdog-update.log` then says "Homebrew has no newer
Sheepdog yet." Try again later, after Homebrew refreshes its tap.

The check sends no version or identifier. Turn it off with **Check for updates** in Settings,
under General. To check right away, pick **Check for Updates…** in Tug's menu. It answers in a
dialog, and **Update Now** there installs the same way the card does.

## Tug's collar

Twelve collars in Settings, Look: Jax, Black Diamond, Golden Spark, Rubie, Lightning, Thunder,
Strawhat, Grapes, Rose, Berserker, PickleJuice and Trunk. Each one colors the collar, the
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
pill, the hand-back card, Settings and the menu bar. Turn off **Dress Tug up for holidays** in
Settings, Look, to keep him plain.

In the same days the alarm barks a holiday tune instead of the plain bark: Auld Lang Syne, Let Me
Call You Sweetheart, The Irish Washerwoman, In the Hall of the Mountain King, Over the River and
Through the Wood, and Jingle Bells. Easter has no tune. Every note is Tug's own woof. The tune plays
only when the alarm sound is one of Tug's, and the warning chime stays a single woof. Turn off
**Bark holiday tunes** in Settings, Sound, to keep the plain bark.

## Settings and features

| Feature       | What it does                                                               |
|---------------|----------------------------------------------------------------------------|
| Calendars     | Signs in to Microsoft and Google, and reads the rest from macOS Calendar.  |
| Join links    | Finds Teams, Zoom, Google Meet, Webex and Slack links in the event.        |
| Let them know | Copies a running late or can't make it line and opens your Slack channel.  |
| Volume        | Unmutes and raises the volume while the alarm plays, then puts it back.    |
| Speakers      | Plays through headphones, built-in speakers, or both at once.              |
| Sounds        | Tug's bark and woof, or any macOS system sound.                            |
| Filters       | Skips tentative events by default, and solo events if you turn that on.    |
| Timing        | Warning times, alarm lead, snooze lengths and snooze count are adjustable. |
| Login         | Starts at login from Settings.                                             |
| Menu bar      | Tug's glyph changes with the alert stage and the menu lists what is next.  |
| Events        | Each meeting in the menu offers Join meeting and Open in Calendar.         |
| Nap time      | Silences real meetings for 1 or 3 hours, until morning, or until woken.    |
| Hours         | Keeps Tug quiet, or down to the countdown, outside your working hours.     |
| Hover         | The glyph says what is next, and each menu item says what it does.         |
| Backup        | Exports settings to a file and imports them on any Mac. Sign-ins stay out. |
| Collar        | Twelve collars for Tug that also color the alarm, pill and hand-back card, or Custom. |
| Outfits       | Holiday outfits for Tug. Dress Tug up for holidays turns them off.         |
| Tunes         | Holiday tunes for the alarm, in barks. Bark holiday tunes turns them off.  |
| Updates       | Checks GitHub once a day for a newer release and offers to install it.     |

Use **Test the alarm** in Tug's menu to see the whole thing without a real meeting. While Tug
naps, the test shows the alarm without sound.
