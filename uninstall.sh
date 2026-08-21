#!/usr/bin/env bash
# Back to a normal Mac. Best-effort teardown: stops the tiling stack,
# restores the native menu bar, unlinks configs (restoring backups
# where install.sh made them). Homebrew packages are left installed.

set -uo pipefail

log() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }

# Manifest written by install.sh: only what IS recorded gets removed,
# so tools and settings that predate omacosy are never touched.
# Pre-manifest installs fall back to the conservative old behavior.
MANIFEST="$HOME/.local/state/omacosy/manifest"
have() { [ -f "$MANIFEST" ] && grep -qxF "$1" "$MANIFEST"; }

# --- 1. Stop the stack ------------------------------------------------------
# Quitting AeroSpace restores windows it was managing.
log "Stopping AeroSpace, the bar, borders"
osascript -e 'quit app "AeroSpace"' 2>/dev/null || true
osascript -e 'quit app "Karabiner-Elements"' 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/com.omacosy.borders.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.omacosy.borders.plist" "$HOME/.local/bin/omacosy-borders"
launchctl unload "$HOME/Library/LaunchAgents/com.omacosy.ffm.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.omacosy.ffm.plist" "$HOME/.local/bin/omacosy-ffm"
launchctl unload "$HOME/Library/LaunchAgents/com.omacosy.dwindle.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.omacosy.dwindle.plist" "$HOME/.local/bin/omacosy-dwindle"
launchctl unload "$HOME/Library/LaunchAgents/com.omacosy.bar.plist" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.omacosy.bar.plist" "$HOME/.local/bin/omacosy-bar"
rm -rf "$HOME/.local/share/omacosy/omacosy-bar.app"
# overview is self-daemonizing (no launchd agent) — kill by pidfile.
# It lives in the mode-700 runtime dir now, but the -L check stays:
# `[ -f ]` follows symlinks, and trusting the contents no further than
# "digits" costs nothing.
PIDFILE="$HOME/.local/state/omacosy/run/overview.pid"
if [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ]; then
  OVERVIEW_PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  case "$OVERVIEW_PID" in
    '' | *[!0-9]*) : ;;
    *) kill "$OVERVIEW_PID" 2>/dev/null || true ;;
  esac
fi
rm -f "$HOME/.local/bin/omacosy-overview" "$HOME/.local/bin/omacosy-toggle"
# The runtime dir goes with ~/.local/state/omacosy at the end of this
# script. These are the leftovers from when all of it lived in /tmp —
# `rm -f` unlinks a planted symlink instead of following it, and the
# sticky bit means another user's file simply refuses to go.
rm -f /tmp/omacosy-*.log /tmp/omacosy-*.err /tmp/omacosy-bar-ws \
  /tmp/omacosy-bar-moved /tmp/omacosy-bar-cheatsheet /tmp/omacosy-ws-switch \
  "/tmp/omacosy-overview-$(id -u).pid" "/tmp/omacosy-overlay-active-$(id -u)" \
  "/tmp/omacosy-user-intent-$(id -u)" "/tmp/omacosy-split-state-$(id -u)" \
  "/tmp/omacosy-guard-bounce-$(id -u)" "/tmp/omacosy-guard-cooldown-$(id -u)" 2>/dev/null || true
rmdir "/tmp/omacosy-spawn-$(id -u).lock.d" 2>/dev/null || true
rm -rf "$HOME/.config/omacosy"

# aerospace-swipe: ONLY if we cloned it — a pre-existing install
# (agent, app, clone) belongs to the user and stays untouched
if have "cloned-aerospace-swipe" && [ -d "$HOME/.local/share/aerospace-swipe" ]; then
  (cd "$HOME/.local/share/aerospace-swipe" && make uninstall) 2>/dev/null || true
  rm -rf "$HOME/.local/share/aerospace-swipe"
  rm -rf "$HOME/.config/aerospace-swipe"
fi

# --- 2. Native menu bar + system gestures back ------------------------------
# Preferred path: restore each key to its RECORDED pre-omacosy value
# (type-aware; ABSENT means it was unset). Fallback for pre-manifest
# installs: hardcoded Apple defaults.
if [ -f "$MANIFEST" ] && grep -q '^default ' "$MANIFEST"; then
  while read -r _ domain key type value; do
    if [ "$type" = "ABSENT" ]; then
      defaults delete "$domain" "$key" 2>/dev/null || true
    else
      defaults write "$domain" "$key" "-$type" "$value" 2>/dev/null || true
    fi
  done < <(grep '^default ' "$MANIFEST")
else
  defaults delete NSGlobalDomain _HIHideMenuBar 2>/dev/null || true
  defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 2
  defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 2
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 2 2>/dev/null || true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 2 2>/dev/null || true
  defaults delete com.apple.dock showMissionControlGestureEnabled 2>/dev/null || true
fi
killall cfprefsd 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall Dock 2>/dev/null || true

# --- 3. Unlink configs, restore backups -------------------------------------
restore() {
  local dst=$1
  [ -L "$dst" ] && rm "$dst"
  # a symlink we displaced (dotfiles managers) comes back first
  local prior
  prior="$(grep -F "$(printf 'prior-symlink\t%s\t' "$dst")" "$MANIFEST" 2>/dev/null | tail -1 | cut -f3)"
  if [ -n "$prior" ] && [ ! -e "$dst" ]; then
    log "Relinking $dst -> $prior"
    ln -sfn "$prior" "$dst"
    return
  fi
  local bak
  bak="$(ls -d "$dst".bak.* 2>/dev/null | sort | tail -1 || true)"
  # never clobber something the user has recreated since
  if [ -n "$bak" ] && [ ! -e "$dst" ]; then
    log "Restoring $bak -> $dst"
    mv "$bak" "$dst"
  fi
}

# configs COPIED for TCC-protected clones are ours to delete; the
# restore() calls below then bring back backups / displaced symlinks
grep '^copied-config ' "$MANIFEST" 2>/dev/null | sed 's/^copied-config //' |
  while IFS= read -r d; do rm -rf "$d"; done

restore "$HOME/.zshrc"
restore "$HOME/.config/starship.toml"
restore "$HOME/.config/aerospace"

# re-enable Karabiner's helper agents we disabled
for agent in Karabiner-Menu Karabiner-NotificationWindow; do
  launchctl enable "gui/$(id -u)/org.pqrs.service.agent.$agent" 2>/dev/null || true
done

# Karabiner's config is a copied real file (its daemons can't read
# ~/Documents). Restore a pre-omacosy config if install backed one up,
# otherwise remove our copy.
if have "had-karabiner-config" && [ -f "$HOME/.config/karabiner/karabiner.json.bak.omacosy" ]; then
  log "Restoring pre-omacosy karabiner.json"
  mv "$HOME/.config/karabiner/karabiner.json.bak.omacosy" "$HOME/.config/karabiner/karabiner.json"
else
  rm -f "$HOME/.config/karabiner/karabiner.json" "$HOME/.config/karabiner/karabiner.json.bak.omacosy"
  rmdir "$HOME/.config/karabiner" 2>/dev/null || true
fi

# Pre-omacosy, ~/.zshrc pointed at the old dotbot repo — relink if
# nothing else restored it and that repo is still around.
if [ ! -e "$HOME/.zshrc" ] && [ -f "$HOME/Documents/config/.dotfiles/zshrc" ]; then
  log "Relinking ~/.zshrc to the legacy dotfiles repo"
  ln -s "$HOME/Documents/config/.dotfiles/zshrc" "$HOME/.zshrc"
fi

# theme-set / theme-next out of ~/.local/bin — only when they are OUR
# symlinks (a user's own script of the same name survives)
for t in theme-set theme-next omacosy-ws omacosy-toggle omacosy-focus-guard omacosy-ws-collapse omacosy-float omacosy-cycle omacosy-update; do
  target="$(readlink "$HOME/.local/bin/$t" 2>/dev/null || true)"
  case "$target" in *omacosy*) rm -f "$HOME/.local/bin/$t" ;; esac
done
rm -f "$HOME/.local/bin/omacosy-helper"

# omarchy theme convention dirs (restore brings back any .bak the
# install displaced — it was created and then orphaned before)
restore "$HOME/Library/Application Support/omarchy"
rm -f "$HOME/.config/omarchy/current/theme"
rmdir "$HOME/.config/omarchy/current" "$HOME/.config/omarchy" 2>/dev/null || true

# --- 4. Korren back to its built-in default theme ---------------------------
KORREN_CFG="$HOME/Library/Application Support/korren/config.toml"
if [ -f "$KORREN_CFG" ]; then
  sed -i '' 's/^name = "omarchy"/name = "default"/' "$KORREN_CFG"
fi

# --- 5. Homebrew packages omacosy itself installed --------------------------
# Only packages the manifest says brew bundle ADDED on this machine —
# anything the user had before is untouched.
if [ -f "$MANIFEST" ] && grep -qE '^brew-(formula|cask) ' "$MANIFEST"; then
  log "Removing Homebrew packages omacosy installed (pre-existing ones stay)"
  grep '^brew-formula ' "$MANIFEST" | awk '{print $2}' \
    | xargs -n1 brew uninstall 2>/dev/null || true
  grep '^brew-cask ' "$MANIFEST" | awk '{print $2}' \
    | xargs -n1 brew uninstall --cask 2>/dev/null || true
fi
if have "installed-homebrew"; then
  echo "Note: Homebrew itself was installed by omacosy; remove it with the"
  echo "official uninstall script if you don't want it."
fi
rm -rf "$HOME/.local/state/omacosy"

cat <<'EOF'

Done. Left in place on purpose:
  - Homebrew packages you already had before omacosy (manifest-tracked;
    without a manifest, all packages stay — remove manually)
  - Karabiner's Caps Lock remap stops once the app is quit/uninstalled.
  - The menu bar returns fully after logging out and back in.
  - Claude desktop's caps-lock dictation shortcut was removed during setup;
    re-enable it in Claude's settings if you used it.
  - If AeroSpace still appears in System Settings -> General -> Login Items, remove it there.
  - The repo itself and your shell tools (fzf, eza, zoxide, ...) are untouched.
EOF
