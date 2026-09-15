# ChoreSplit

An iOS app for roommates who keep having the same argument about the washing up.

Everyone signs in on their own phone, creates or joins a group for their place, and invites the
others with a code. Chores are worth **1 to 4 points** based on how hard, how physical and how
long they are, and the group rates those values **anonymously**, so nobody can quietly overprice
their own chore. To finish a task you add a **video** of the done job; the others watch it and
rate how well it went — also anonymously — and that decides what it pays. Whoever falls
furthest below their fair share gets handed the next job automatically. Reminders are spoken
out loud in a real voice.

Built with SwiftUI and SwiftData on the phone, and [Supabase](https://supabase.com) for
accounts, the shared database, video storage and live updates.

---

## Getting started

Requires Xcode 16 or later; deploys to iOS 18+.

```bash
open ChoreSplit.xcodeproj
```

Out of the box the app has no Supabase project to talk to, so it opens on a **Connect a
Supabase project** screen. You can look around before setting one up.

### Trying it without a server (debug builds)

The **Try the on-device demo instead** button on that screen — or the `--demo` launch
flag — opens a three-person household that lives entirely on the phone, with chores, ratings,
proof videos and a few days of lopsided history. It's the pass-the-phone version of the app:
the people button switches who's holding it.

To see the signed-in, multi-phone screens with made-up data and no server, use
`--preview-shared`:

```bash
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared                 # a running group's feed
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --setup         # a group being set up
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --setup --invite
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --group-menu
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --signed-out    # welcome screen
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --profile       # new-account profile
xcrun simctl launch booted com.choresplit.ChoreSplit --preview-shared --groups        # your groups
```

Alongside `--demo`, a few more flags open specific sheets: `--scores`, `--add-task`,
`--complete` (add `--attach-demo-video` for a generated clip), and `--scroll-to-ratings`.

The simulator has no camera, so recording a proof video only works on a real iPhone. To try
choosing one instead, drop any clip onto the simulator window (or run `xcrun simctl addmedia
booted clip.mp4`) and it lands in Photos.

### Connecting Supabase

**1. Create a project** at [supabase.com](https://supabase.com). The free tier is enough to start.

**2. Create the database.** In the dashboard's **SQL Editor**, paste in
[`supabase/migrations/20260914000000_choresplit.sql`](supabase/migrations/20260914000000_choresplit.sql)
and run it. With the [Supabase CLI](https://supabase.com/docs/guides/cli) you can instead run
`supabase link --project-ref <your-ref>` and then `supabase db push`. This creates the tables,
the security rules, the functions the app calls, the private `proof-videos` storage bucket,
and turns on live updates for the shared tables.

**3. Give the app your project's keys.** Copy the template and fill it in from **Project
Settings → API Keys** (the project URL, and the `anon` / publishable key):

```bash
cp Config/Supabase.example.plist ChoreSplit/Supabase.plist
```

`ChoreSplit/Supabase.plist` is gitignored. The publishable key is designed to ship inside apps —
the database's row-level security is what protects the data — but there's no reason to publish
it in a public repo either. Xcode picks the file up automatically; rebuild.

**4. Turn on Google sign-in.**

1. In [Google Cloud Console](https://console.cloud.google.com), under **APIs & Services**,
   set up the **OAuth consent screen** (External, your app name and a support email).
2. Under **Credentials**, create an **OAuth client ID** of type **Web application**. Add
   `https://<your-project-ref>.supabase.co/auth/v1/callback` as an authorized redirect URI, and
   copy the client ID and secret.
3. In Supabase, under **Authentication → Sign In / Providers → Google**, enable it and paste
   them in.
4. Under **Authentication → URL Configuration → Redirect URLs**, add
   `choresplit://login-callback`. This is how the sign-in sheet hands control back to the app.

**5. Turn on phone sign-in.** Under **Authentication → Sign In / Providers → Phone**, enable
it and connect an SMS provider (Twilio, MessageBird, Vonage or Textlocal). Real texts cost
money per message. While testing, add a few **test phone numbers** with fixed codes in the
same settings — they sign in without sending anything.

That's everything. Build, run, and sign in.

### Running the tests

The app's tests (80) run in Xcode with ⌘U, or:

```bash
xcodebuild test -project ChoreSplit.xcodeproj -scheme ChoreSplit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The database's security rules have their own tests (37). They run the migration inside an
embedded Postgres — no Docker, no Supabase project needed — and act out scenarios as
different signed-in people: a stranger trying to read a group, someone rating their own task,
a phone trying to award itself points, and so on.

```bash
cd supabase/tests && npm install && npm test
```

---

## How it works

### 1. Accounts, groups and invites

There's no separate sign-up form. Signing in with **Google** or a **phone number** (a texted
six-digit code) for the first time creates the account; you then pick the name and emoji your
roommates will see.

A **group** is a household. Whoever creates it is its **owner**, and it gets an eight-character
invite code like `K7P4-QX9A` — no look-alike characters, so it survives being read out loud.
**Invite friends** shares a message with the code and a `choresplit://join` link; tapping the
link on a phone with the app installed opens the join screen with the code filled in. The join
screen shows the group's name and size before you commit, so a mistyped code can't drop you
into a stranger's flat.

You can belong to several groups and switch between them from the **group menu** (the people
button at the top of the feed), which also lists members and their points, invites more
people, and signs you out. If the owner leaves, the longest-standing member becomes owner; when
the last member leaves, the group is deleted. The owner can issue a new invite code, which
stops the old one working without removing anyone.

### 2. Setting up a group

Everyone does setup **on their own phone**:

1. **The owner creates the group** and chooses how often the scoreboard resets (3 days, a
   week, a fortnight), then shares the invite code.
2. **Everyone adds chores** — the jobs they care about, and what they think each is worth.
   There's a library of 23 common chores to start from.
3. **Everyone rates the others' chores, anonymously.** The rating screen hides what the
   proposer said, because seeing "they said 4 out of 5" first drags almost everyone towards 4.
4. **The owner starts the group**, which hands out the first round of chores fairly.

Anyone who joins after that is included from their next turn.

### 3. Points: 1 to 4

Each chore is judged on three things, because roommates argue about three different things:

| Input | Rated | Why it's separate |
|---|---|---|
| **Difficulty** | 1–5 | A chore can be quick but disgusting — scrubbing the toilet |
| **Physical effort** | 1–5 | Hauling recycling down three flights is not the same as wiping a counter |
| **Time** | minutes | A laundry cycle is long but easy |

Each input becomes a **level from 1 to 4**, and the chore is worth the **average of the three
levels, rounded to a whole point**:

- **Difficulty and effort** are stretched from 1–5 onto 1–4 (1 → 1, 3 → 2.5, 5 → 4). Raters
  keep five steps so they can say "a bit worse than average".
- **Time** is banded, so a few minutes either way doesn't change the answer:
  up to 10 min → 1, up to 20 → 2, up to 40 → 3, longer → 4.

| Chore | Difficulty | Effort | Time | Levels | Points |
|---|---|---|---|---|---|
| Water the plants | 1 | 1 | 10 min | 1 · 1 · 1 | **1** |
| Wash up after dinner | 2 | 2 | 20 min | 1.75 · 1.75 · 2 | **2** |
| Scrub the toilet | 4 | 3 | 15 min | 3.25 · 2.5 · 2 | **3** |
| Clean the shower and bath | 4 | 4 | 30 min | 3.25 · 3.25 · 3 | **3** |
| Clean the oven | 5 | 4 | 60 min | 4 · 3.25 · 4 | **4** |

A chore's final value is the proposer's numbers averaged with everyone's anonymous ratings, so
one person can't inflate their own chore.

### 4. Anonymous ratings, enforced by the server

When you finish a task, it appears under **Give ratings** for everyone else. They watch the
video and give it stars:

```
1 star → half points    2 stars → three quarters    3 stars or more → full points
```

Bad work is penalised in half-point steps but never zeroed — the job still got done — and
there's no bonus above full points, so every payout stays on the 1–4 scale. If nobody rates
within 48 hours, the task pays full points: silence isn't treated as criticism.

**Nobody can see who rated what — not even by inspecting their own phone.** The database only
ever returns *your own* ratings and votes. Everyone else's arrive as totals from functions on
the server: how many people have rated, and — only once at least two have — the average and the
notes. In a three-person flat, showing a lone rating is the same as naming the person who left
it, so it stays hidden. Notes come back sorted, so their order gives nothing away.

**Points are decided by the server, too.** A phone can finish a task, but only the database
functions can settle it and set what it paid. When the last eligible person rates, the server
settles the task straight away; tasks whose rating window has closed are settled the next time
any phone checks in. If a phone sends a task marked as settled with points attached — an old
offline copy, or someone tampering — the server keeps its own values. The payout formula
exists in both Swift and SQL, and a test checks they agree for every chore value and score.

The rules also stop you rating your own task, rating the same task twice, pricing a chore you
added, finishing a task that isn't yours, joining a group without its code, or reading anything
in a group you're not in. The database tests act out each of these.

In the on-device demo, where there's no server, ratings are stored against a salted hash of the
rater instead, and the same reveal threshold applies.

### 5. Who gets the next chore

Your **fair share** is the cycle's total points split by group size, plus anything carried over.
Fall more than 10% below it and ChoreSplit hands you extra chores until you catch up. The next
turn of a recurring chore always goes to whoever is furthest behind — the rota follows the
points, not a fixed rotation.

Chores are handed out largest-first, and the planner stops as soon as you're back inside
tolerance. One subtlety: giving someone a chore raises *everyone's* target, because the fair
share is a slice of the work on the table. The planner re-derives every deficit after each pick,
which is what stops it finding a new person "behind" forever; there's a regression test for that.

With several phones in a group, **only one at a time** runs this job: a phone claims it on the
server for ten minutes before handing anything out, so two phones opening at once can't both
assign the same work. When a cycle ends, half of any remaining imbalance carries into the next
one, capped at ±10 points.

### 6. Syncing between phones

Every change is **saved on the phone first and queued**, so ticking something off never waits
on the network and the app works on the train. The queue is sent oldest-first; a refresh then
pulls the group down and updates the phone's copy in place, keeping what only lives on that
phone — reminders, the local video file, and the salts that recognise your own ratings.

- **Offline:** the queue waits, in order, and sends when you're back. A refresh doesn't undo a
  change that hasn't gone up yet.
- **Refused:** if the server rejects a change (say, a rule forbids it), it's dropped so it can't
  block the ones behind it, the group menu shows why, and the next refresh shows the server's
  version.
- **Live:** while a group is open, Supabase Realtime tells the phone when someone else changes
  something, and it refreshes shortly after. It also checks in when the app comes to the
  foreground, every couple of minutes, and on pull-to-refresh.
- **Videos:** a proof video is uploaded to the private `proof-videos` bucket before the finished
  task is saved, at `<group id>/<task id>.mp4`; only members of that group can read it. Other
  phones stream it through a link that expires after an hour. Once ratings close, the person who
  uploaded it deletes it from the server and the phone.
- **Tasks assigned from another phone** get a reminder scheduled on yours when they arrive.

Signing out or leaving a group clears that group's copy from the phone, so the next account on a
shared phone never sees someone else's household.

### 7. The feed

After setup there are no tabs — one feed, top to bottom:

- **Top bar** — the app name, **+** to add a task, and the people button for the group menu.
- **Scoreboard** — a card for each person with the points they've *earned* this week, highest
  first, leader crowned. Tap one for their breakdown: every finished task, what it was worth,
  what it paid, and why.
- **Your tasks** — tap the circle to finish one, tap the row to change its reminder, or
  long-press to skip.
- **Give ratings** — directly under your tasks: other people's finished tasks, with their video.

**Finishing a task** needs a video: record one, or choose one from Photos. **Mark as done** stays
locked until one is attached. Clips are capped at one minute (a longer one keeps its first
minute) and re-encoded at medium quality. The app asks for camera and microphone access the
first time you record; choosing from Photos needs no permission.

**Adding a task** covers what, who (you, anyone in the group, or "fewest points"), when, and the
reminder, in one sheet. A new task's points update live as you set its difficulty, effort and
time.

### 8. Voice reminders

iOS won't run text-to-speech from a notification, so ChoreSplit synthesises the sentence to an
audio file ahead of time and attaches it as the notification's **custom sound**. When the
reminder fires, the phone says:

> "Sam, the kitchen bins are due tonight. That's four points."

— with the app closed. The person is named first, numbers are spelled out (so "4" isn't read as
a time), and the points go last. Wording is editable, with a preview button.

Notification sounds must be in `Library/Sounds`, under 30 seconds, and 16-bit linear PCM.
`AVSpeechSynthesizer` produces 32-bit float, so the file is declared as Int16 and `AVAudioFile`
converts on the way out; clips are length-checked afterwards, because iOS silently falls back
to the default chime for anything too long.

---

## Project layout

```
ChoreSplit/
├── ChoreSplitApp.swift          App entry, notification delegate
├── RootView.swift               Demo / connect Supabase / signed-in app, and invite links
├── Models/                      SwiftData: Household, Roommate, Chore, Assignment, ratings,
│                                and PendingOperation (the sync queue)
├── Services/
│   ├── Backend/                 Supabase client and config, database row types, RemoteStore,
│   │                            AuthStore (sign-in, profile), GroupStore (create, join, leave)
│   ├── Sync/                    SyncEngine (queue, refresh, live updates), SnapshotApplier,
│   │                            model ↔ row mapping
│   ├── PointsEngine             Chore values → points; quality → payout
│   ├── FairnessEngine           Fair shares, next-in-line, catch-up planning, cycle roll
│   ├── Scores                   Earned points for the scoreboard and rating queue
│   ├── ProofVideoStore          Convert, trim, store, thumbnail and delete proof videos
│   ├── HouseholdActions         Every state change in one place, reported to sync
│   ├── NotificationService      Scheduling, reminder sentences
│   ├── VoiceReminderService     Speech, and speech → notification sound file
│   └── …                        Anonymity tokens, starter chores, debug demo data and clips
├── Design/                      Theme and shared components
└── Features/
    ├── Account/                 Welcome, phone sign-in, profile, "connect Supabase"
    ├── Groups/                  Your groups, create, join, invite, group menu, group setup,
    │                            and the debug preview
    ├── Home/                    The feed, finish-with-video, rating cards, score breakdown,
    │                            add task, reminders
    ├── Chores/                  Chore editor and starter library
    └── Onboarding/              The on-device demo's pass-the-phone setup
Config/
├── Info.plist                   The choresplit:// URL scheme
└── Supabase.example.plist       Template for ChoreSplit/Supabase.plist
supabase/
├── migrations/                  Schema, row-level security, functions, storage, realtime
└── tests/                       The security rules, tested in an embedded Postgres
```

The app's 80 tests cover the points formula, anonymity tokens, both rating flows, the
scoreboard, proof videos, the fairness engine, and sync — applying the server's copy, sending
queued changes in order, staying intact offline, uploading a video before its task, and never
sending the same change twice. Sync is tested against an in-memory stand-in for Supabase.

---

## Known limits

- **Apple requires an extra sign-in option before App Store release.** App Review guideline 4.8
  says an app offering a third-party login like Google must also offer an equivalent
  privacy-focused one — in practice, **Sign in with Apple**. It isn't built, since the app was
  asked for Google and phone sign-in; Supabase supports Apple as a provider, so it's the next
  thing to add before submitting.
- **Invite links need the app installed and aren't always tappable.** They use a custom
  `choresplit://` scheme, which some messaging apps don't turn into links — which is why the
  invite message includes the code. Links that open a web page when the app isn't installed
  need a website and universal links.
- **Text messages cost money.** Phone sign-in bills per SMS through your provider, and Supabase
  rate-limits how often codes can be sent.
- **Offline edits are last-write-wins.** If two people edit the same chore offline, whichever
  syncs last wins. Ratings and points can't conflict, because the server decides them.
- **You, as the project owner, can see who rated what** in the Supabase dashboard. The rules keep
  roommates from seeing it, not the person running the database.
- **A chore's value is shown from the first vote.** It has to be, to price the chore — so with a
  single voter, the proposer could work out that vote from the average. Quality ratings, which
  are the sensitive ones, stay hidden until two are in.
- **Videos can't be watched after ratings close.** They're deleted from the phone and the server.
- **No settings screen.** Group rules use fixed defaults beyond the cycle length chosen at
  creation: catch-up chores beyond 10% behind, scores hidden until 2 ratings, a 48-hour rating
  window.
- **Reminders need notification permission.** Without it nothing is scheduled.
