# External API — design

Status: **agreed**, open questions answered (section 11); implementation next.

The API is a thin entry point into machinery Meniscus already has: the mini banner, the compact
wing pattern, the live activity queue, the quiet rules and the per-activity toggles. It adds no
layout system, colors or timing model of its own.

## 1. Goals and non-goals

Goals:

- Let scripts, command line tools, Shortcuts and agents such as Claude Code tell the user
  something short in the notch, or show that a longer task is running.
- Keep the island calm: no flicker for short tasks, nothing that stays forever, nothing louder
  than the built-in notices.
- Never let a caller decide how the island looks, and never show an icon the caller merely
  claims.

Non-goals for v1:

- Rich content (images, progress percentages, buttons, custom colors or durations).
- Notifications for when the Mac is locked or the island is hidden. If a notice can't be shown,
  it is dropped or waits, as described below; it is not delivered elsewhere.
- Presets for known sources (icons and texts per app). Sources are only what can be verified.
- Any network access. Every channel is local; Meniscus still makes no network requests.

## 2. Two primitives

### `notify`

A short notice, shown as one mini banner (`MiniBanner`). Fields:

| Field | Required | Limits | Notes |
| --- | --- | --- | --- |
| `title` | yes | 60 characters | One line; truncated with an ellipsis in the banner. |
| `subtitle` | no | 80 characters | The banner's second line, in grey. |
| `state` | no | `info` (default), `success`, `attention` | See section 3. |
| `action` | no | trusted channels only | See section 7. |

### `activity`

A task that runs for a while, addressed by the caller's `id`:

- `start(id, title, subtitle?, state = info, timeout?)` registers it. Starting an id that is
  already running restarts it (new title, state and start time).
- `update(id, title?, subtitle?, state?)` changes what it says. An update also counts as a sign
  of life for the timeout.
- `end(id, state = success, title?, subtitle?)` finishes it, maybe with a closing banner (section
  5). Ending an id that isn't running does nothing and isn't an error.

Ids are scoped by source (section 7): two sources can use the same id without touching each
other's activities. An id is at most 128 characters.

Text fields are always `title` and `subtitle`, in every primitive and channel. There is no
`message` field.

### Event order

Callers such as Claude Code hooks run asynchronously, so their calls can arrive out of order: an
`end` can reach Meniscus before the `start` it ends, and the late `start` would then leave an
activity running with nothing left to end it. So:

- Every `activity` call carries `at`, the time the event happened, in milliseconds since 1970
  (wall clock, the same on every process of the Mac). The CLI takes it when it starts, before it
  reads its input; `--at` overrides it. A call without `at` (Shortcuts) gets the time it arrives.
- Meniscus keeps, for each source and id, the time of the last event it applied, and ignores any
  event older than that. A `start` older than an `end` already applied is dropped, so it can't
  bring the activity back.
- At equal times, `end` wins over `update`, and `update` over `start`.
- An ended id's last time is kept for 10 minutes, then forgotten; at most 1,000 per source, oldest
  first.

`notify` has no id, so it has no ordering; deduplication (section 7) handles repeats.

## 3. States

| State | Meaning | Look | Banner time |
| --- | --- | --- | --- |
| `info` | Something happened or is happening. | White, no glyph on the right. | 3 s |
| `success` | Something finished as expected. | White checkmark on the right. | 3 s |
| `attention` | The user should look: something waits for them or went wrong. | Exclamation mark on the right in the system orange; the only accent color. | 5 s |

The island stays black and white. `attention` is the only state with color, and only its small
glyph is tinted; title and subtitle stay white and grey. The caller doesn't choose the color,
the layout, the duration or whether a haptic plays. `attention` banners play the same haptic as
other important notices when haptics are on.

## 4. Icons: verified, not declared

The left tile of the banner, and the left wing of an activity, shows the source's icon only when
Meniscus verified it itself. A caller can't pass an icon or claim to be an app.

| Channel | Icon |
| --- | --- |
| URL scheme | Always the neutral icon. A URL can come from any web page or app; its origin can't be known. |
| CLI | The icon of the app the command runs in, found by Meniscus (below). If it can't be determined reliably, the neutral icon. |
| App Intents (Shortcuts) | What the system tells: an intent doesn't learn which shortcut or app ran it, so the Shortcuts icon when the intent runs from Shortcuts, otherwise the neutral icon. |

Finding the app for the CLI: the app (not the CLI) takes the connecting process's id from the
socket (`LOCAL_PEERPID`, public) and walks up its parent processes (`sysctl` with `KERN_PROC`,
public) until it reaches a process that `NSRunningApplication` knows as a regular app with a
bundle, for example Terminal, iTerm, Ghostty or Visual Studio Code. If the walk reaches `launchd`
first (tmux and screen servers, `ssh`, launch agents, cron), the source is unknown and the icon
is neutral. Nothing the CLI says about itself is used for the icon.

The neutral icon is the SF Symbol `app.badge` on the banner tile.
Pictures are never taken from the caller.

## 5. Nothing stays forever; no flicker

### Banner time

A banner shows for its state's time (section 3), at most 5 s, then the island folds back. A
banner waiting behind more important notices keeps its time: its clock starts when it is shown
(section 6). A banner that waits too long is dropped: `info` and `success` after 15 s, `attention`
after 2 minutes.

### Activity lifetime

An activity ends with `end`, or quietly when nothing was heard from it for its timeout: no banner
and no error, it just leaves the queue. The default timeout is 30 minutes since the last `start`
or `update`, and a caller can ask for between 1 minute and 2 hours.

### Indicator delay

A short task shouldn't make the island twitch. So an activity is invisible at first: the
indicator in the compact island appears only once the activity has run for the **indicator
delay**, 10 s by default (a setting, 3–60 s). What `end` shows depends on whether the indicator
was ever visible:

| `end` state | Indicator not yet visible (short task) | Indicator was visible (long task) |
| --- | --- | --- |
| `info` | nothing | short banner (3 s) |
| `success` | nothing | short banner (3 s) |
| `attention` | banner (5 s) | banner (5 s), with the haptic |

`update(state: attention)` while running shows an `attention` banner right away (the user must
see it even if the indicator isn't visible yet) and keeps the activity running; the indicator, if
visible, shows the attention glyph until the state changes again.

### In the compact island

A visible activity uses the wing pattern, with no text in the wings:

- left: the source's icon (section 4);
- right: a small activity indicator, or the attention glyph when the state is `attention`;
- when one source has several activities running: the indicator and their number, for example
  `2`, shortened rather than cut.

The title and subtitle show in banners and when the island is opened (the expanded island lists
running activities with their titles), never in the wings. Several activities of one source are
always one grouped activity in the compact island. Banners are never grouped: each activity that
ends gets its own banner, one after another (section 6).

## 6. Priorities and the queue

### Order

From most to least important:

1. Upcoming meeting; Mac low battery; Bluetooth device low battery.
2. Direct feedback to the user's own action, shown at once: keyboard layout, "Saved", a device the
   user just connected.
3. External `attention`.
4. Charging; music (now playing, track change).
5. External `info` and `success`, and external activity indicators.

### Mapping onto `LiveActivity.Priority`

Today's values and the proposed ones:

| Activity | Today | Proposed |
| --- | --- | --- |
| `interaction` (file drag) | 100 | 100 |
| `meeting` | 90 | 90 |
| `lowBattery` | 80 | 80 |
| `deviceLowBattery` | 75 | 78 |
| `inputSource` | 60 | 70 (direct feedback) |
| `captureSaved` (`confirmation`) | 55 | 70 (direct feedback) |
| `bluetoothDevice` (`confirmation`) | 55 | 70 (direct feedback) |
| **external `attention`** | — | 65 |
| `charging` | 70 | 60 |
| `trackChange` (`confirmation`) | 55 | 55 |
| `nowPlaying` (`ongoing`) | 50 | 50 |
| **external `info`, `success`** | — | 45 |
| **external activity indicator** | — | 44 (behind its own banners) |
| `shelf` (`background`) | 0 | 0 |

The changes to built-in order are that direct feedback moves above charging, and confirmations
split into direct feedback (70) and music (55). A new case `externalAttention = 65` and
`external = 45` join the enum.

### Queue changes

The queue stays a pure value type with one wake-up for the next change. External notices need
three additions:

1. **Clock starts when shown.** Today a transient activity's `expiresAt` is set when posted, so a
   banner waiting behind a meeting reminder can expire unseen. External banners carry a duration
   and a "drop if not shown by" date instead; `expiresAt` is set when the banner first becomes
   `current`. Built-in activities keep today's behavior.
2. **First in, first out for external banners.** Today equal priorities favor the newest. For
   banners of one source (for example several Claude sessions ending), Meniscus keeps its own
   FIFO and posts only the head to the queue, so they show one after another, each for its full
   time.
3. **Grouping.** All running activities of one source are posted as one `LiveActivity` whose id is
   the source; the count lives beside it like the shelf count does.
4. **At most three end banners in a row.** When a source's FIFO holds more than three end banners
   in a row, the first three show one after another and the rest collapse into one banner,
   "Claude finished · 2 more" (the adapter's title with the count of those left).

### Quiet rules

External notices obey the same rules as built-in ones, with no exceptions:

- Hidden while an app is in full screen on the island's screen (the presentation guard).
- Left out of screenshots, recordings and screen sharing when that setting is on.
- Banners wait while the island is open and show after it closes, if still within their wait.
- Each channel and each source has a switch (section 10); when off, calls succeed and nothing
  shows.

These are the "smart silence" rules: the existing ones, nothing new. Schedules and silence
during calls are not in v1. macOS doesn't tell apps about Focus, so external notices ignore it.

With music playing, a running activity's indicator (45) stays behind the equalizer (50); an
`attention` notice (65) shows over music and gives the notch back to it.

## 7. Channels and trust

### URL scheme — untrusted

`meniscus://v1/notify?title=Build%20finished&subtitle=api&state=success`

- Any web page, document or app can open a URL, so the URL scheme is treated as anonymous.
- **Only `notify`**: text and state. No `action`, no `activity` (an anonymous caller could start
  activities it never ends).
- Text limits as in section 2; longer text is cut before display, control characters removed.
- **Global rate limit** (the source can't be told apart): at most 3 banners in 10 s and 20 per
  hour; more are dropped.
- **Deduplication**: the same title, subtitle and state within 60 s shows once.
- Its own switch, **off by default**.

### CLI `meniscus` — trusted

```
meniscus notify "Build finished" --subtitle api --state success
meniscus activity start  --id build-42 "Building api" --timeout 1h
meniscus activity update --id build-42 --subtitle "Linking"
meniscus activity end    --id build-42 --state success "Build finished"
meniscus activity end    --id build-42 --quiet          # ends without a banner
meniscus notify "Tests failed" --state attention --open "https://ci.example/run/42"
meniscus status                                          # API version, channels on or off
```

**Transport:** a Unix domain socket at
`~/Library/Application Support/Meniscus/api.sock`, in a folder only the user can read (`0700`),
the socket itself `0600`. Browsers can't open Unix sockets, and web pages can't reach the file
system, so this channel can't be reached from a browser. Messages are one JSON object per line
with an answer per request. The app checks the peer's user id (`getpeereid`) and drops anything
not from the logged-in user.

The CLI binary ships inside the app (`Contents/Helpers/meniscus`). Installing it needs no
administrator rights: **Install Command Line Tool** links it as `~/.local/bin/meniscus`, and if
that folder isn't on `PATH`, Settings shows the line to add to `~/.zshrc`. **Copy Path** copies the
binary's full path for anyone who'd rather call it directly or link it elsewhere.

**The CLI never gets in the way of the tool calling it:** it answers within 0.5 s, never prompts,
and exits 0 when a notice was accepted, queued or silenced. It exits non-zero only for invalid
input (2) or when Meniscus isn't running (3). It never launches Meniscus.

**Trusted extras:**

- `action` on click, one of: open an `https` URL, open a file in its default app, or bring the
  source app forward. Without an `action`, a click brings the source app forward, as macOS
  notifications do; with an unknown source, a click does nothing. A banner takes clicks only
  within its own area while shown; everywhere else the island keeps letting clicks through as
  today. URL scheme banners never take clicks.
- Rate limit per source (the verified app, or "unknown" as one shared source): 10 banners per
  minute, 100 per hour.
- Deduplication as for the URL scheme, but per source.

### App Intents (Shortcuts) — trusted

Intents: **Show Notice in Notch**, **Start Notch Activity**, **Update Notch Activity**, **End
Notch Activity**, with the same fields as the CLI. Intents run inside Meniscus, so only Shortcuts,
Siri and Spotlight on this Mac can call them. Rate limit per source as for the CLI, the source being
Shortcuts. Actions on click: open a URL or a file.

On macOS 27, `linkd` runs App Intents only for apps signed with a team identifier
(`requiresValidatedBundle`); ad-hoc signed builds are rejected before the intent runs. Until
Meniscus is signed with a developer team, Shortcuts users call the CLI from **Run Shell Script**
instead. Its source then resolves to unknown (the shell runs under a Shortcuts helper, not an app),
so banners show the neutral icon.

## 8. Claude Code

Checked against the current hooks reference and agent view documentation (October 2026).

### Hooks used

| Hook | When Claude Code runs it | Meniscus call |
| --- | --- | --- |
| `UserPromptSubmit` | A prompt starts a turn (also scheduled tasks, `/loop` iterations, reports from background subagents and messages from other sessions). | `activity start --id <session_id> --timeout 2h` "Claude is working" |
| `Stop` | Claude finished responding. Not after an interrupt (Esc); API errors run `StopFailure` instead. | `activity end --id <session_id> --state success` "Claude finished" |
| `StopFailure` | The turn ended on an API error (`error` holds the type, for example a rate limit). | `activity end --id <session_id> --state attention` "Claude stopped", subtitle from the error type |
| `SessionEnd` | The session ends (`/clear`, exit, logout, resume elsewhere). | `activity end --id <session_id> --quiet` |
| `Notification`, `permission_prompt` | Claude waits for a permission and the prompt has waited about six seconds without typing. | `activity update --id <session_id> --state attention` "Claude is waiting for you" |
| `Notification`, `elicitation_dialog` | An MCP server asks the user something, after the same six seconds. | same as `permission_prompt` |
| `Notification`, `agent_needs_input` | A background session starts waiting for input, while agent view is open in a terminal. | `notify --state attention` "Claude is waiting for you" |
| `Notification`, `agent_completed` | A background session finished or failed, while agent view is open. | `notify --state success` "Claude finished", only as a fallback (below) |

Every hook input carries `session_id`, so it is the activity id: parallel sessions never update
or end each other's activities. The subtitle is the project folder's name (the last part of
`cwd`), so banners from parallel sessions can be told apart; full paths are never shown. The
hook's own `message` and `title` (on `Notification`) are not shown as they are; they map at most
to our `subtitle`.

### The ordinary turn

1. The user sends a prompt: `UserPromptSubmit` starts the activity with a 2-hour timeout, so a
   long task doesn't vanish quietly. Nothing shows yet.
2. A short answer: `Stop` comes before the indicator delay. `end(success)` on an activity whose
   indicator never appeared shows **nothing**. This is what keeps everyday back-and-forth silent;
   no separate rule is needed.
3. A long task: after 10 s the compact island shows the terminal's icon and the indicator. On
   `Stop`, the indicator goes away and a short "Claude finished" banner shows.
4. Claude needs a permission mid-task: `permission_prompt` turns the activity to `attention` and
   shows "Claude is waiting for you" at once, even for a task under 10 s, because the user has to
   act.
5. The user interrupts with Esc: no `Stop` comes. The next `UserPromptSubmit` of the same session
   restarts the activity; `SessionEnd` ends it; otherwise it times out quietly after 2 hours.
6. Two sessions work at once: the compact island shows one grouped activity, the indicator and
   `2`. When they finish, each gets its own banner, one after another, with its project name;
   from the fourth in a row on, the rest collapse into "Claude finished · N more".
7. Hooks are asynchronous, so a quick turn's `Stop` can reach Meniscus before its
   `UserPromptSubmit`. Each call carries the time its hook started (section 2), and the late
   `start` is ignored.

There is no "Claude is waiting for your answer" after a finished turn: `Stop` doesn't say whether
Claude asked a question, and `idle_prompt` would bring back a notice after every short answer.
Neither a question mark heuristic nor `idle_prompt` is used.

### Background sessions

`agent_needs_input` and `agent_completed` are sent by the Claude Code process that shows agent
view, not by the background session itself. The documentation doesn't say which `session_id`
they carry; since the hook runs in the agent view process, it is most likely that session's own
id, not the background session's. So:

- They never touch activities: they are plain `notify` calls and don't use their `session_id`.
- Background sessions run their own hooks, so their own `UserPromptSubmit` and `Stop` already
  drive their activities by their real `session_id`. `agent_completed` is then a duplicate, and
  the adapter drops it when any Claude activity of the same source ended in the last 10 seconds.
  It still helps when a background session's hooks can't reach Meniscus.
- `agent_needs_input` also fires for an agent team teammate's setup question and for auto mode's
  billing notice; both deserve `attention` too, so it is used as is.
- The adapter logs the raw fields of these two events (in the `api` log category, without paths
  or text) so the guess about `session_id` can be confirmed on a real Mac before relying on it.

Background sessions are started by a supervisor process, not from a terminal, so their parent
chain may end at `launchd`; their activities then show the neutral icon (section 4).

### Texts

The mapping runs in the app: `meniscus hook claude-code` forwards only the hook's event name,
session id, notification type and the last part of `cwd`, never the prompt, Claude's answer or
full paths. So the adapter's texts are in the app's string catalog and follow the user's
language, like the rest of Meniscus:

| English | Russian |
| --- | --- |
| Claude is working | Claude работает |
| Claude finished | Claude закончил |
| Claude finished · %lld more | Claude закончил · ещё %lld |
| Claude is waiting for you | Claude ждёт вас |
| Claude stopped | Claude остановился |

### Setup

The CLI has a built-in adapter that reads the hook's JSON from standard input, so users need no
`jq` or scripts. The command uses the full path, because hooks don't always get the shell's
`PATH`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "$HOME/.local/bin/meniscus hook claude-code", "async": true }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "$HOME/.local/bin/meniscus hook claude-code", "async": true }] }],
    "StopFailure":      [{ "hooks": [{ "type": "command", "command": "$HOME/.local/bin/meniscus hook claude-code", "async": true }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "$HOME/.local/bin/meniscus hook claude-code", "async": true }] }],
    "Notification": [{
      "matcher": "permission_prompt|elicitation_dialog|agent_needs_input|agent_completed",
      "hooks": [{ "type": "command", "command": "$HOME/.local/bin/meniscus hook claude-code", "async": true }]
    }]
  }
}
```

`async` keeps the hooks from ever delaying Claude; the event times (section 2) put their calls back
in order. The adapter maps `hook_event_name` and `notification_type` to the calls in the table
above, always exits 0 and prints nothing. The same mapping can be written with plain
`meniscus activity …` commands and `jq` for users who want to change it. Settings can copy this
snippet; it never edits the user's Claude Code settings itself.

The source for these calls is the terminal app Claude Code runs in, verified as in section 4.

## 9. Versioning

- The version is in every entry point: the URL path (`meniscus://v1/…`), a `"v": 1` field in
  each socket message (the CLI adds it), and `meniscus status` / the **Get Notch API Version**
  intent report what the running app supports.
- Within a major version, changes are additive only: new optional fields, new states or actions.
  Unknown fields are ignored; an unknown `state` is shown as `info`; an unknown action is dropped
  and the notice still shows.
- A breaking change becomes `v2`. The app keeps accepting `v1` for at least two releases after
  `v2` ships and says so in the release notes; `meniscus status` lists the versions it accepts.
- A CLI newer than the app falls back to the app's version and drops what it can't send; it tells
  the user once on standard error, never by failing the calling tool.
- App Intents keep their identifiers; a breaking change adds new intents and deprecates the old
  ones.

## 10. Settings

In **Settings → Live Activities**, a section **External notices**:

- **CLI and Shortcuts** — on by default.
- **Links (`meniscus://`)** — off by default.
- **Show running tasks after** — the indicator delay, 10 s.
- **Sources** — every source seen so far (verified app, Shortcuts, "Unknown", "Links") with its
  own switch and last time seen. Sources appear only after their first call; there are no
  presets.
- **Install Command Line Tool** (to `~/.local/bin`, with the `PATH` hint), **Copy Path** and
  **Copy Claude Code Hooks**.

Developer: simulations for a notice in each state, a short and a long activity, four parallel
activities ending (three banners and a collapsed one), and a late `start` after its `end`.

## 11. Decisions

Answers to the open questions of the first draft:

1. Smart silence is the existing quiet rules; schedules and calls are not in v1.
2. Focus is ignored.
3. The URL scheme is off by default.
4. The URL scheme offers only `notify`.
5. With music, music wins over a running activity; `attention` shows over music by priority.
6. No "waiting for your answer" after a finished turn: no question mark heuristic, no
   `idle_prompt`.
7. A click on a trusted banner without an `action` brings the source app forward.
8. After three end banners in a row, the rest collapse into "Claude finished · N more".
9. The neutral icon is `app.badge`.
10. No `PostToolUse` refresh. The default activity timeout is 30 minutes; the Claude Code adapter
    starts activities with a 2-hour timeout. They restart on `UserPromptSubmit` and end on
    `Stop`, `StopFailure` or `SessionEnd`.
11. Banner times as proposed: 3 s for `info` and `success`, 5 s for `attention`; waits of 15 s and
    2 minutes.
