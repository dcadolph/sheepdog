<p align="center"><img src="../art/tug-head.png" width="96" alt="Tug"></p>

<h1 align="center">Using sheepdog</h1>

sheepdog reads every calendar in macOS Calendar, including Google and Exchange, and escalates in
three steps as each meeting gets closer. Each step is described below in the order it happens.

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

## Msg team

Add your team's Slack channels in Settings, under Slack. Use **Copy link** on a channel in Slack
and paste it in, with a name such as #team. The alarm then shows **Msg team** next to
**Hold my place**.

- **Running late** copies "Running a few minutes late to Design review." and opens the channel.
  The alarm drops to the countdown pill, so the meeting is still tracked.
- **Can't make it** copies "I can't make Design review." and opens the channel. The meeting
  counts as skipped, the same as **I'm skipping this one**.
- With more than one channel, pick one first. Paste and press Return in Slack to send.
- sheepdog never signs in to Slack and never sends anything itself.

## Settings and features

| Feature    | What it does                                                               |
|------------|----------------------------------------------------------------------------|
| Calendars  | Reads every calendar in macOS Calendar, including Google and Exchange.     |
| Join links | Finds Teams, Zoom, Google Meet, Webex and Slack links in the event.        |
| Msg team   | Copies a running late or can't make it line and opens your Slack channel.  |
| Volume     | Unmutes and raises the volume while the alarm plays, then puts it back.    |
| Speakers   | Plays through headphones, built-in speakers, or both at once.              |
| Sounds     | Tug's bark and woof, or any macOS system sound.                            |
| Filters    | Skips tentative events by default, and solo events if you turn that on.    |
| Timing     | Warning times, alarm lead, snooze lengths and snooze count are adjustable. |
| Login      | Starts at login from Settings.                                             |
| Menu bar   | Tug's glyph changes with the alert stage and the menu lists what is next.  |
| Events     | Each meeting in the menu offers Join meeting and Open in Calendar.         |
| Nap time   | Silences real meetings for 1 or 3 hours, until morning, or until woken.    |
| Hover      | The glyph says what is next, and each menu item says what it does.         |
| Backup     | Exports settings to a file and imports them on any Mac. Sign-ins stay out. |
| Themes     | Eleven color themes for the alarm, the countdown and the hand-back card.   |

Use **Test the alarm** in Tug's menu to see the whole thing without a real meeting.
