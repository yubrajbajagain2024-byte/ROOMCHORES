# ChoreSplit

An iOS app for roommates who keep having the same argument about the washing up.

Chores are worth **points** based on how hard, how physical and how long they are. The
whole household rates those values **anonymously**, so nobody can quietly overprice their
own chore. Finish a chore and your housemates rate how well it went — also anonymously —
and that decides what it actually pays. Whoever falls furthest below their fair share gets
handed the next job automatically. Reminders are spoken out loud in a real voice.

Built with SwiftUI and SwiftData. Everything stays on the device; there is no account and
no server.

---

## Getting started

```bash
open ChoreSplit.xcodeproj
```

Pick an iPhone simulator and run (⌘R). Requires Xcode 16 or later; deploys to iOS 18+.

In a debug build the first setup screen has a **Fill with a demo household** button, which
loads a three-person flat with chores, ratings and a few days of lopsided history — handy
for seeing the balancing rules react without doing ten minutes of setup first. The same
household can be loaded straight from the command line:

```bash
xcrun simctl launch booted com.choresplit.ChoreSplit --demo --tab standings
```

Run the tests with ⌘U, or:

```bash
xcodebuild test -project ChoreSplit.xcodeproj -scheme ChoreSplit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## How it works

### 1. Setup is something the household does together

Setup runs as a pass-the-phone flow rather than one person filling in a form:

1. **Name the place** and choose how often the scoreboard resets (3 days, a week, a fortnight).
2. **Add everyone.** Anyone who is away a lot can be put on a reduced share — a half-share
   roommate is measured against half the target, so "even" does not have to mean "identical".
3. **Everyone adds chores.** Each person takes a turn adding the jobs they care about and
   saying what they think each is worth. There is a library of 23 common chores to start from.
4. **Everyone re-rates everyone else's chores, anonymously.** The final value of a chore is
   the average of the proposer's estimate and every anonymous rating.

The proposer's numbers are **hidden by default** on the rating screen. Seeing "they said
4 out of 5" first drags almost everyone towards 4, which would make the averaging pointless.

### 2. Points

Each chore is scored on three things, because roommates argue about three different things:

| Input | Scale | Why it's separate |
|---|---|---|
| **Difficulty** | 1–5 | A chore can be quick but disgusting — scrubbing the toilet |
| **Physical effort** | 1–5 | Hauling recycling down three flights is not the same as wiping a counter |
| **Time** | minutes | A laundry cycle is long but easy |

```
points = 1.4 × difficulty  +  1.4 × effort  +  0.28 × minutes  −  1.5      (minimum 1)
```

Which lands roughly where you would expect:

| Chore | Difficulty | Effort | Time | Points |
|---|---|---|---|---|
| Take the bins out | 1 | 2 | 5 min | 4 |
| Wash up after dinner | 2 | 2 | 20 min | 10 |
| Vacuum the living room | 2 | 3 | 25 min | 13 |
| Clean the shower and bath | 4 | 4 | 30 min | 18 |
| Do the grocery run | 3 | 4 | 60 min | 25 |

Scoring on time alone would under-pay the toilet; scoring on effort alone would under-pay
the laundry.

### 3. Anonymous ratings

There are two kinds, and both are anonymous:

- **Value ratings** decide what a chore is *worth*. Everyone but the proposer rates it, and
  the point value settles on the household average.
- **Quality ratings** decide what a finished chore *paid*. When you mark something done, the
  points sit provisional until your housemates say how it went.

```
1 star → 0.6×    2 → 0.8×    3 → 1.0×    4 → 1.1×    5 → 1.2×
```

Three stars means "done properly" and pays full value. Bad work is penalised but never
zeroed — the job still got done. The bonus for excellence is deliberately small, so the
incentive is to do chores rather than to farm compliments. If nobody rates within the
window (default 48 hours), the chore pays face value: silence is not treated as criticism.

**How the anonymity actually works.** A rating stores a salted SHA-256 of the rater's ID
instead of the ID, with a fresh salt per chore and per assignment. That stops you rating
twice, stops the stored rows reading as "who said what", and stops the same person being
linked across two different chores. Anonymous notes are shuffled before display so their
order gives nothing away.

The protection that matters most socially is the **reveal threshold**: scores stay hidden
until at least 2 ratings are in (configurable). In a three-person flat, showing a lone
rating is the same as naming the person who left it.

This is deliberate obfuscation, not a cryptographic guarantee — someone with the device,
the salt and the short list of household member IDs could brute-force the mapping. It is
built to survive housemates, not forensics.

### 4. Who gets the next chore

Your **fair share** is the cycle's total points split by household size, adjusted for
anyone on a reduced share, plus anything you carried over. Fall more than 10% below it
(configurable) and ChoreSplit hands you extra chores until you catch up. The next occurrence
of a recurring chore always goes to whoever is furthest below their share — the rota follows
the points, not a fixed rotation.

Chores are handed out largest-first, and the planner stops as soon as you are back inside
tolerance rather than overshooting you into a surplus. There is one subtlety worth knowing
about: giving someone a chore raises *everyone's* target, because the fair share is a slice
of the work actually on the table. Assigning 12 points to one person in a three-person flat
closes their gap by 8 and opens a 4-point gap for each of the others. The planner re-derives
every deficit from the growing pool after each pick, which is what stops it finding a new
person "behind" on every launch and handing out work forever. There is a regression test
for exactly that.

When a cycle ends, **half** of any remaining imbalance carries into the next one, capped at
±30 points — so a lopsided week is not simply forgiven, but it is always recoverable.

Auto-assignment can be turned off entirely, in which case the Standings tab gets an
**Even it out** button that shows exactly what it is about to hand out, and to whom, before
it does it.

### 5. Voice reminders

iOS will not run text-to-speech from a notification, so ChoreSplit synthesises the sentence
to an audio file ahead of time and hands it to the notification as its **custom sound**.
When the reminder fires the phone says:

> "Sam, the kitchen bins are due tonight. That's four points."

rather than playing a generic chime — and it does that with the app closed.

The sentence is written for the ear: the person is named first so they know it is for them,
numbers are spelled out (so speech does not read "4" as a time), and the point value goes
last because that is the part that gets anyone off the sofa. Every reminder's wording is
editable, with a preview button.

The mechanics that constrain this: notification sounds must live in `Library/Sounds`, be
under 30 seconds, and be 16-bit linear PCM. `AVSpeechSynthesizer` hands back 32-bit float
buffers, so the file is declared as Int16 while the processing format stays as the
synthesiser's own, letting `AVAudioFile` convert on the way out. Rendered clips are length-
checked afterwards, because iOS silently falls back to the default sound for anything too
long — which would look exactly like the feature being broken. Clips are deleted when their
reminder is cancelled, and orphans are pruned on launch.

Voice and speaking rate are picked in Settings. More natural voices appear once downloaded
in iOS Settings → Accessibility → Spoken Content → Voices.

---

## Project layout

```
ChoreSplit/
├── ChoreSplitApp.swift        App entry, notification delegate
├── RootView.swift             Setup vs. running
├── Models/                    SwiftData: Household, Roommate, Chore, Assignment, ratings
├── Services/
│   ├── PointsEngine           Chore values → points; quality → payout
│   ├── FairnessEngine         Standings, next-in-line, catch-up planning, cycle roll
│   ├── AnonymityService       Salted rater tokens
│   ├── VoiceReminderService   Speech, and speech → notification sound file
│   ├── NotificationService    Scheduling, reminder sentences
│   ├── HouseholdActions       Every state change in one place
│   ├── StarterChores          Library of common chores
│   └── DemoData               Debug-only sample household
├── Design/                    Theme and shared components
└── Features/
    ├── Onboarding/            Household → roommates → build chores together
    ├── Home/                  Today, assignment detail, voice reminder editor
    ├── Chores/                Library, editor, chore detail
    ├── Rating/                Anonymous rating inbox, both rating types
    ├── Leaderboard/           Standings, rebalance sheet
    └── Settings/              Household rules, voice, roommates
```

`ChoreSplitTests/` has 34 tests covering the parts where being wrong is expensive: the
points formula, the anonymity tokens, the two rating flows, and the fairness engine —
including a regression test that the catch-up planner actually terminates.

---

## Known limits

- **One device.** A household shares one phone (or iPad on the counter), switching who is
  active with the avatar button in the top right. There is no sync, no account and no
  server. Adding CloudKit sharing would mean a `CKShare` per household and a paid developer
  account; the data layer is kept clean enough that it is a contained change, but it is not
  built.
- **Anonymity is social, not forensic.** See above.
- **Reminders need notification permission.** Without it the voice clip is still rendered,
  but the system will not deliver it.
