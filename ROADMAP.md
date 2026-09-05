# Roadmap

Direction, not promises. Ordered roughly by pull.

## Known gaps (honest list)

- **External display brightness (DDC).** The brightness pill controls
  the built-in panel via DisplayServices; external monitors need a
  DDC/I²C stack (what MonitorControl does). Deliberately out of
  scope so far.
- **Re-dwindle for moved windows.** The split hint decides where the
  NEXT window opens, so windows *moved* into a workspace (throws, the
  undock collapse) still land as flat siblings. Hyprland re-tiles them
  binarily; we don't yet.
- **Super + mouse-drag resize (and move).** Hyprland binds Super +
  right-drag to resize the window toward the grabbed corner, and Super +
  left-drag to move it; omarchy users expect both. The pieces exist:
  mouse events carry modifier flags (so no keyboard tap is needed),
  `aerospace resize` takes `--window-id`, and `omacosy-ffm` already
  holds Accessibility and knows the window under the cursor. Needs an
  active CGEvent tap on right-mouse events (a step up from ffm's
  listen-only monitor, worth a Permissions note), and a decision
  between `aerospace resize` per drag tick (~25ms per call, so ~30Hz,
  visibly stepped) and direct AX `setSize` (smooth, but needs a
  measurement that AeroSpace re-normalizes a fast resize stream the
  way it does a native edge drag).
- **Focus guard vs. typing.** An app that yanks focus while you are
  actively typing (input < 2s old) is indistinguishable from a
  user-driven switch and slips through. A denylist for known
  offenders (messengers on non-visible workspaces) is the likely
  escalation.
- **macOS support matrix.** Built and tested on macOS 26 (Tahoe),
  Apple Silicon, one external display. Sequoia and Intel are
  unknown territory — reports welcome.

## The bar (was: a measured experiment)

`helper/bar.swift` IS the bar now — sketchybar is gone, and with it the
sixteen shell plugins, the popup guard that polled the cursor, and the
watcher daemon whose only job was triggering it. It started as a slice
built alongside sketchybar to answer one question with numbers. Run a
second copy stacked under the real one with `OMACOSY_BAR_STACK=1` if you
ever want that comparison again:

```
swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight \
  -framework DisplayServices \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker helper/bar-info.plist \
  -o /tmp/omacosy-bar helper/bar.swift &&
codesign -f -s "Apple Development" --identifier com.omacosy.bar /tmp/omacosy-bar &&
/tmp/omacosy-bar &
```

It exists to price one question: how much of the bar's latency is the
work, and how much is the process boundaries? Measured on this machine,
same event, from signal received to pixels drawn:

| path | mean | max |
|---|---|---|
| sketchybar (`spaces.sh`, excluding its fork and trigger IPC) | 164.79 ms | 191.71 ms |
| native, model held in memory | 2.50 ms | 3.65 ms |

The difference is not language. It is that `spaces.sh` spawns five
`aerospace` CLI calls (~23 ms each) to ask what just happened, while the
native process already holds the window model — fed by the same SkyLight
notifications three daemons are separately subscribed to today. The slow
path (which windows exist, where) costs ~65 ms and runs off the main
queue on window create/destroy only, never on a switch.

The right cluster is now there too — weather, wifi, bluetooth, brightness,
volume, battery, clock, activity — reading their sources directly rather
than forking a script that forks `pmset`, `osascript`, `networksetup` and
`ipconfig`. Every pill has a real publisher behind it (IOPS, CoreAudio,
DisplayServices, SCDynamicStore, IOBluetooth), so only the clock and the
weather run on timers. Per-pill repaint, measured:

| pill | sketchybar plugin | native |
|---|---|---|
| volume | 370 ms | 1.9 ms |
| weather | 270 ms | 5.4 ms |
| wifi | 120 ms | 1.8 ms |
| brightness | 70 ms | 1.7 ms |
| battery | 60 ms | 2–19 ms (first paint warms the font) |

Findings worth keeping even if this goes no further:

- Asking for a font family and **verifying you got it** makes the
  Hiragino class of bug unrepresentable; sketchybar's `--default` failed
  silently, and nothing in the output ever said so.
- Running the CLI calls inline on the main queue blocked rendering for
  7.6 s under contention. The architecture only pays if subprocess work
  never sits on the path a frame travels — the same discipline, applied
  one level in.
- **AeroSpace monitor ids are not stable across a hotplug.** Undock and
  the built-in stops being monitor 2 and becomes monitor 1; a cached id
  then answers `Invalid monitor ID`, the snapshot returns empty, and the
  bar keeps rendering the last set it knew — stale, with no error. Found
  within an hour of first running it, by unplugging. The id is now
  re-resolved by display NAME on every screen-parameters change, which is
  the same trap `borders.swift` hit with a stale CG-to-Cocoa flip.

- **Bluetooth privacy is judged by the RESPONSIBLE process, not the
  binary.** IOBluetooth does not fail when ungranted, it aborts the whole
  process: SIGABRT, exit 134, empty stderr, and this machine writes no
  crash report, so it looks like a silent death. An embedded Info.plist
  and a stable signature are not enough — launched from a shell, the
  responsible process is the shell, and the grant is not there. That is
  why `watcher.swift` gets away with prompting: launchd starts it. The
  bar therefore never prompts; it checks `CBCentralManager.authorization`
  and hides the pill unless the grant is already held, which it will be
  once this runs as a launchd agent like every other daemon here.
- **The SSID needs the Location grant AND a bundled binary**, and
  neither alone is enough. Without the grant every source refuses —
  CoreWLAN returns nil, `ipconfig` prints `<redacted>`, `networksetup`
  claims you are not associated. With the grant an unbundled binary
  STILL reads nil: measured with authorisation held, services on and
  updates running. A throwaway `.app` built to isolate the variable
  read the name immediately, so the bar ships inside a minimal bundle
  and the pill prints the network. The bundle is a new TCC subject,
  which costs a round of re-grants (bluetooth, automation, and the
  palette read if the clone sits under ~/Documents).

Popups are there now — calendar, volume (slider plus output devices),
brightness (slider plus display settings), wifi and bluetooth. They are
plain views in their own window rather than bar items named by
convention, so there is nothing for a shell guard to grep and nothing to
leak. Closing follows the rule the shell guard approximates by polling:
tracking areas on both surfaces, checked a beat later so that crossing
the gap from bar to popup does not read as leaving.

The media capsule and per-display bars are in as well. Spotify broadcasts
its own state and the payload already carries the track, so the pill
repaints (2.1 ms, against media.sh's 480 ms) without asking anything —
the only subprocess left is the one a click sends, where 20 ms does not
show. There is now one window per screen, each drawing its own workspace
set, and the media capsule sits centred or in the left cluster depending
on whether that screen has a notch — read from `safeAreaInsets` rather
than asked of a helper. The two-display case has now had its real test,
and it found two bugs that a single display could not show: the chip
filter hid empty guest workspaces (right undocked, where the guest set
is parked on the one display; wrong docked, where 11-19 ARE the second
display's own set), and the accent marking "you are here" keyed off the
globally focused workspace, so the display without focus could not say
which workspace it was showing. Both fixed; each surface now marks its
own visible workspace.

The weather popup and fullscreen hiding close the list. One j1 fetch now
feeds both the pill and its popup; weather.sh needs a cache file written
atomically because a click can read it mid-write, and in one process the
struct IS the cache, so that race cannot be expressed.

Hiding is the one place sketchybar has it easier: its windows sit at
layer -20, below normal windows, so a fullscreen window simply covers
them. This bar draws above windows and has to decide for itself, and
geometry alone is not enough — measured, on a notched display the notch
inset (32 px) and the gap a tiled window leaves for the bar (33 px) are
the same edge, so an ordinary tiled window reads as fullscreen by height.
WIDTH separates them: `--no-outer-gaps` means the window takes the 8 px
side gaps too, and a tiled one never does. Note that
`%{window-is-fullscreen}` reported `false` on a window that measured
1512x950 — aerospace's own flag could not be used for this.

The apple menu is the last of the parity list: About This Mac, System
Settings, Lock Screen, Sleep, Restart, Shut Down, Next Theme. Its popup
aligns to its LEFT edge, being the leftmost thing on the bar. "Reload
Bar" has no counterpart on purpose — there is no config to re-read and
the theme is watched, so a row that did nothing would be worse than a row
that is absent.

What is left is not features but standing: per-display bars, notch-aware layout, and
fullscreen hiding. Memory, measured after the move: the stack idles at 155MB of physical
footprint (325MB RSS — RSS counts shared framework pages once per
process, so it roughly doubles the truth). The bar is 27MB of footprint,
54MB RSS, against a bare sketchybar's 24MB RSS — AppKit costs more
resident memory than a lean C program, and no amount of architecture
argues that away. What pays for it is `omacosy-watcher` no longer
existing (~20MB) and every plugin's fork storm no longer happening. Call
memory a wash; the win was always latency, and it should be described
that way.

Still separate processes: borders, the overview and ffm. An
earlier draft of this file called folding them in "the obvious next
step", which the measurements do not support as stated.

A minimal AppKit daemon with one empty window is 32.5MB resident before
it does anything. borders is 30MB RSS / 11MB footprint — essentially all
runtime tax for one CAShapeLayer ring — and overview is 37MB either way,
being the one that actually holds capture buffers. Folding both into the
bar reclaims two AppKit runtimes, about 55-65MB, and deletes real
duplication: bar and borders each hold their own WindowServer connection
draining overlapping create/destroy/move/resize events, three kqueue
watches sit on the same theme directory, and both handle display hotplug
separately, which is why each hit its own version of that bug.

Against it: blast radius (a borders crash currently leaves the bar up)
and the permission surface. TCC grants are tied to the signature, so one
binary holding Screen Recording, Bluetooth and Accessibility loses all
three whenever a rebuild invalidates it, where today they fail
independently.

So: borders is the clear candidate — nearly pure runtime tax, the same
event stream, the same hotplug logic, no extra grant. Overview is
marginal, needing Screen Recording and holding capture buffers either
way. ffm stays out precisely to keep its Accessibility grant isolated,
and the dwindle daemon is gone entirely — a focus hook runs
`omacosy-helper` for a few milliseconds instead of a resident process.
Borders stays out because at 9.2MB with no AppKit it is already the
cheapest thing here.

Never a lock screen (`loginwindow` is protected) or a Notification
Center replacement.

## Wants

- **omarchy's scrolling layout** (`Super+L`, per-workspace) — the
  second layout omarchy ships; AeroSpace has no native equivalent,
  so this would be another daemon-grafted behavior.
- **More themes.** `themes/<name>/` is copy-a-directory; omarchy's
  MIT-licensed palettes drop in. The easiest PR in the repo.
- **Upstreaming.** The aerospace-swipe macOS 26 fixes are offered
  upstream (acsandmann/aerospace-swipe #29/#30) — the engine now lives
  in-tree as `omacosy-gesture`, so a merge is a courtesy, not a
  dependency; an AeroSpace
  window-created hook would delete our SkyLight dependency for the
  bar's window events.
