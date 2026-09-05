# Why AeroSpace (and why not Amethyst, yabai, or our own)

Status: living doc. First written 2026-08-13, mid-frustration, so the
costs below are real ones we hit, not brochure claims.

## The actual constraint

macOS has no replaceable window manager. Every third-party "tiling WM"
is a *manager of other apps' windows* built from the same small API
surface, which forces one of two designs:

- **A. Accessibility API + native Spaces** (Amethyst): workspaces are
  real macOS Spaces. Gestures, Mission Control, and fullscreen all
  behave natively — and every workspace switch plays the system's
  ~300 ms slide animation, which cannot be disabled by supported
  means. Layout engines here are dynamic/xmonad-style, not manual
  trees.
- **B. Accessibility API + offscreen stashing** (AeroSpace): workspaces
  are virtual; hidden windows get parked as slivers at the screen
  edge. Switching is instant and the config model is i3-like — and the
  cost is every weirdness we live with: Mission Control shows a window
  pile, native-fullscreen apps sit outside the model, gestures need a
  helper daemon, helpers must filter sliver windows.
- **C. Private SkyLight APIs via Dock injection** (yabai's scripting
  addition): transcends both — real z-order control, instant Space
  switching, opacity. Requires partially disabling SIP. For a setup
  meant to be adopted by other people, that is a non-starter, and
  yabai *without* the scripting addition collapses back into roughly
  design B with less omarchy-shaped config.

There is no fourth design. This is the whole decision space.

## Why AeroSpace won for omacosy

omacosy's goal is omarchy (Hyprland/i3) muscle-memory on macOS. That
decides it:

- i3-flavored config and manual tile trees map 1:1 onto omarchy
  keybindings. Amethyst's auto-layouts don't.
- Instant workspace switching is the feel of Super+1..9 on Hyprland.
  The Space-switch animation kills it.
- The `aerospace` CLI is what the whole polish layer scripts against:
  sketchybar workspace icons, the swipe daemon, focus helpers,
  `omacosy-toggle`. Amethyst has no comparable scripting surface.

## The honest cost ledger (design B's tax)

- Trackpad swipes are a daemon (`omacosy-gesture`, absorbed from
  aerospace-swipe), and daemons have Accessibility grants that die whenever the
  binary changes unsigned. Fixed by signing all helpers with a stable
  identity in install.sh — grants now survive rebuilds.
- Native-fullscreen apps live on their own Space, outside AeroSpace's
  model. Mitigation: prefer AeroSpace fullscreen (Super+F); treat the
  green button as an escape hatch, not a habit.
- Floating windows obey macOS z-order, not a float layer. The ffm
  helper is float-aware (never raises tiles over floats, never steals
  focus from a parked cursor), but "floats pinned above the active
  app" is impossible without design C.
- Borders and focus are polled helpers; their smoothness is our own
  code's quality, on us to optimize — not an AeroSpace ceiling.

## Should we build our own?

Tempting after a bad week, but the wall is the API surface, not the
incumbents' engineering. A from-scratch manager without SIP-disable
must again pick design A or B, and after a year of work would arrive
at the same ceilings AeroSpace and Amethyst already occupy — minus
their decade of edge-case fixes (the AX quirks per app, the Spaces
races, the display-reconfigure paths). What we'd own is a third copy
of the same trade-offs.

Where owning code *does* pay, we already do it: the glue daemons
(ffm, borders, swipe patches, sketchybar) are ours, they're where the
perceived quality lives day-to-day, and they're small enough to make
excellent. That — plus upstreaming fixes to AeroSpace where the
engine itself hurts — is the leveraged version of "build our own".

Revisit this doc if Apple ever ships real WM extension points, or if
the SIP calculus changes.
