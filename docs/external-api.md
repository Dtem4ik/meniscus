# External API — design

Status: **draft for review**, nothing implemented yet. The API is a thin entry point into
machinery Meniscus already has: the mini banner, the compact wing pattern, the live activity
queue, the quiet rules and the per-activity toggles. It adds no layout system, colors or timing
model of its own.

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

- `start(id, title, state = info)` registers it. Starting an id that is already running restarts
  it (new title, state and start time).
- `update(id, title?, subtitle?, state?)` changes what it says. An update also counts as a sign
  of life for the timeout.
- `end(id, state = success, title?, subtitle?)` finishes it, maybe with a closing banner (section
  5). Ending an id that isn't running does nothing and isn't an error.

Ids are scoped by source (section 7): two sources can use the same id without touching each
other's activities. An id is at most 128 characters.

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

The neutral icon is an SF Symbol on the banner tile (`app.badge`, to be confirmed in review).
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

A visible activity uses the wing pattern: the source icon on the left, a short value on the
right, both sides as wide as the wider one, shortened rather than cut (`ViewThatFits`):

1. title and count, `Claude is working · 2`
2. the count alone, `2`, with a small activity indicator
3. the indicator alone

When a source has several activities running with the same title, the island shows **one**
grouped activity with the count. Banners are never grouped: each activity that ends gets its own
banner, one after another (section 6).

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
| **external `info`, `success`, activity indicator** | — | 45 |
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
3. **Grouping.** Running activities of one source with the same title are posted as one
   `LiveActivity` whose id is the group key; the count lives beside it like the shelf count does.

### Quiet rules

External notices obey the same rules as built-in ones, with no exceptions:

- Hidden while an app is in full screen on the island's screen (the presentation guard).
- Left out of screenshots, recordings and screen sharing when that setting is on.
- Banners wait while the island is open and show after it closes, if still within their wait.
- Each channel and each source has a switch (section 10); when off, calls succeed and nothing
  shows.

macOS doesn't tell apps about Focus, so external notices don't follow it (see open questions).

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
- Its own switch, **off by default** (proposed; see open questions).

### CLI `meniscus` — trusted

```
meniscus notify "Build finished" --subtitle api --state success
meniscus activity start  --id build-42 "Building api"
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

The CLI binary ships inside the app (`Contents/Helpers/meniscus`). Settings offers to link it to
`/usr/local/bin/meniscus`, or the user adds it to `PATH`.

**The CLI never gets in the way of the tool calling it:** it answers within 0.5 s, never prompts,
and exits 0 when a notice was accepted, queued or silenced. It exits non-zero only for invalid
input (2) or when Meniscus isn't running (3). It never launches Meniscus.

**Trusted extras:**

- `action` on click, one of: open an `https` URL, open a file in its default app, or bring the
  source app forward. A banner with an action takes clicks only within its own area while shown;
  everywhere else the island keeps letting clicks through as today.
- Rate limit per source (the verified app, or "unknown" as one shared source): 10 banners per
  minute, 100 per hour.
- Deduplication as for the URL scheme, but per source.

### App Intents (Shortcuts) — trusted

Intents: **Show Notice in Notch**, **Start Notch Activity**, **Update Notch Activity**, **End
Notch Activity**, with the same fields as the CLI. Intents run inside Meniscus, so only Shortcuts,
Siri and Spotlight on this Mac can call them. Rate limit per source as for the CLI, the source being
Shortcuts. Actions on click: open a URL or a file.

## 8. Claude Code

Checked against the current hooks reference (October 2026).

### Hooks used

| Hook | When Claude Code runs it | Meniscus call |
| --- | --- | --- |
| `UserPromptSubmit` | A prompt starts a turn (also scheduled tasks, `/loop` iterations, reports from background subagents and messages from other sessions). | `activity start --id <session_id>` "Claude is working" |
| `Stop` | Claude finished responding. Not after an interrupt (Esc); API errors run `StopFailure` instead. | `activity end --id <session_id> --state success` "Claude finished" |
| `StopFailure` | The turn ended on an API error (`error` holds the type, for example a rate limit). | `activity end --id <session_id> --state attention` "Claude stopped", subtitle from the error type |
| `Notification`, `permission_prompt` | Claude waits for a permission. | `activity update --id <session_id> --state attention` "Claude is waiting for you" |
| `Notification`, `elicitation_dialog` | An MCP server asks the user something. | same as `permission_prompt` |
| `Notification`, `agent_needs_input` | A background session waits for input (only while agent view is open in a terminal). | `notify --state attention` "Claude is waiting for you" |
| `Notification`, `agent_completed` | A background session finished or failed (only while agent view is open). | `notify --state success` "Claude finished" |
| `SessionEnd` | The session ends (`/clear`, exit, logout, resume elsewhere). | `activity end --id <session_id> --quiet` |

Every hook input carries `session_id`, so it is the activity id: parallel sessions never update
or end each other's activities. The subtitle is the project folder's name (the last part of
`cwd`), so banners from parallel sessions can be told apart; full paths are never shown.

### The ordinary turn

1. The user sends a prompt: `UserPromptSubmit` starts the activity. Nothing shows yet.
2. A short answer: `Stop` comes before the indicator delay. `end(success)` on an activity whose
   indicator never appeared shows **nothing**. This is what keeps everyday back-and-forth silent;
   no separate rule is needed.
3. A long task: after 10 s the compact island shows "Claude is working". On `Stop`, the indicator
   goes away and a short "Claude finished" banner shows.
4. Claude needs a permission mid-task: `permission_prompt` turns the activity to `attention` and
   shows "Claude is waiting for you" at once, even for a task under 10 s, because the user has to
   act.
5. The user interrupts with Esc: no `Stop` comes. The next `UserPromptSubmit` of the same session
   restarts the activity; if none comes, the activity times out quietly. To keep a long task from
   timing out, the adapter refreshes it from `PostToolUse` at most once a minute (optional).
6. Two sessions work at once: the compact island shows one grouped "Claude is working · 2". When
   they finish, each gets its own banner, one after another, with its project name.

"Claude is waiting for your answer" after a finished turn (Claude asked a question) can't be told
apart reliably from "Claude finished": `Stop` doesn't say whether the last message is a question.
`idle_prompt` fires after about a minute without input after any turn, so using it would bring
back a notice after every short answer. Both are left out of v1 (see open questions).

### Background sessions

`agent_needs_input` and `agent_completed` add `attention` and `success` notices for background
sessions, and only while agent view is open. A background session also runs its own `Stop` hooks,
so the same finish could be reported twice; the adapter drops `agent_completed` when an activity
with the same session id ended within the last 10 s. Which `session_id` these two notifications
carry (the background session's or the viewing one's) isn't documented; it has to be checked
before relying on the deduplication.

### Setup

The CLI has a built-in adapter that reads the hook's JSON from standard input, so users need no
`jq` or scripts:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "meniscus hook claude-code", "async": true }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "meniscus hook claude-code", "async": true }] }],
    "StopFailure":      [{ "hooks": [{ "type": "command", "command": "meniscus hook claude-code", "async": true }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "meniscus hook claude-code", "async": true }] }],
    "Notification": [{
      "matcher": "permission_prompt|elicitation_dialog|agent_needs_input|agent_completed",
      "hooks": [{ "type": "command", "command": "meniscus hook claude-code", "async": true }]
    }]
  }
}
```

`async` keeps the hooks from ever delaying Claude. The adapter maps `hook_event_name` and
`notification_type` to the calls in the table above, always exits 0, and prints nothing (a
`UserPromptSubmit` hook's output would otherwise be added to the conversation). The same mapping
can be written with plain `meniscus activity …` commands and `jq` for users who want to change
it. Settings can copy this snippet; it never edits the user's Claude Code settings itself.

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
- **Install command line tool…** and **Copy Claude Code hooks**.

Developer: simulations for a notice in each state, a short and a long activity, and two parallel
activities ending.

## 11. Open questions

1. **Smart silence.** There is no feature by that name yet; this design reads it as the existing
   quiet rules (full screen, screen capture, banners waiting while the island is open, switches).
   Did you mean something more, for example a do-not-disturb schedule or muting external notices
   during calls?
2. **Focus.** macOS doesn't tell apps about Focus (we dropped the filter). Is it fine that external
   notices ignore Focus?
3. **URL scheme off by default?** It is the channel a web page could use. Off by default is safer
   but means a setup step for every user who wants it.
4. **Activities over the URL scheme.** The design allows only `notify` there. Is that enough?
5. **Grouped activity and music.** With both a running task and music, which wins in the compact
   island? The design puts external indicators (45) below music (50), so music wins.
6. **"Claude is waiting for your answer" after a finished turn.** Leave it out (as designed), or
   guess from the last message ending in a question mark, or use `idle_prompt` despite the extra
   notices?
7. **Default click for trusted banners without an action.** Bring the source app forward (for
   Claude Code: the terminal it runs in), or do nothing?
8. **Many sessions ending at once.** Each gets its own banner, one after another. Above some number
   (say three), should the rest collapse into one "Claude finished · 3 more"?
9. **Neutral icon.** `app.badge`, `bell` or the Meniscus icon?
10. **Long tasks and the 30-minute timeout.** Refresh from `PostToolUse` (one extra quick process
    per tool call, run in the background), or just a longer default timeout for Claude Code?
11. **Banner times.** 3 s for `info`/`success` and 5 s for `attention`, with `attention` waiting up
    to 2 minutes behind other notices. Good, or should `attention` wait longer?
