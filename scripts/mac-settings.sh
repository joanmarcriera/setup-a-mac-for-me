#!/bin/bash
#
# mac-settings.sh - interactive menu to toggle macOS settings (mouse, trackpad, Dock,
# Finder, keyboard, screenshots, menu bar...) using only tools built into macOS.
# No Homebrew, no Xcode command line tools, no sudo, no admin account needed.
#
# Each run reads the CURRENT state of every setting, so you can come back any time
# and flip things on or off. Turning a setting off deletes the key, which hands it
# back to the macOS default.
#
# Usage:
#   bash mac-settings.sh              open the menu
#   bash mac-settings.sh --dry-run    open the menu, but print commands instead of running them
#   bash mac-settings.sh --list       print every setting with its current state and exit
#   bash mac-settings.sh -h           this help
#
# In the menu: pick a section by number, then type item numbers to toggle them
# (e.g. "1 4 7"). Changes are only queued until you press "a" to apply.
# Before applying, every touched preference domain is exported to
# ~/Library/Application Support/mac-settings/backup-<timestamp>/ (restore one with
# `defaults import <domain> <file>`).
#
# Get it on a fresh Mac without git (curl is built in):
#   curl -fsSL https://raw.githubusercontent.com/joanmarcriera/setup-a-mac-for-me/main/scripts/mac-settings.sh -o ~/mac-settings.sh
#   bash ~/mac-settings.sh
#
# Works with macOS /bin/bash 3.2.

set -u

dry=false
mode=menu
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry=true ;;
    --list|-l) mode=list ;;
    -h|--help) sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $arg (try -h)" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This script only works on macOS." >&2
  exit 1
fi

macos_version=$(sw_vers -productVersion 2>/dev/null || echo 0)
macos_major=${macos_version%%.*}

# When piped (curl ... | bash) stdin is the script itself; read answers from the terminal.
if [[ "$mode" == menu && ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then
  exec </dev/tty
fi

# ---------------------------------------------------------------------------
# The settings table.
#
#   add SECTION "Label" EFFECT "SPEC[;SPEC...]"
#
#   EFFECT  what it takes for the change to show up:
#             dock / finder / ui / cc = restart Dock / Finder / SystemUIServer / ControlCenter
#             app    = relaunch the affected apps
#             logout = log out and back in (trackpad, mouse and keyboard settings)
#   SPEC    "scope domain key type value"   (one `defaults write`, space separated)
#             scope = u (user) or h (`defaults -currentHost`); type = bool|int|float|string
#           The FIRST spec decides whether the setting shows as on.
#           "fn:NAME" instead calls NAME_state / NAME_on / NAME_off below.
#   ON  = write every spec.  OFF = delete every key (back to the macOS default).
# ---------------------------------------------------------------------------
SECTIONS=()
S=() L=() E=() P=()
add() {
  local s
  for s in "${SECTIONS[@]:-}"; do [[ "$s" == "$1" ]] && break; s=; done
  [[ -z "${s:-}" ]] && SECTIONS+=("$1")
  S+=("$1"); L+=("$2"); E+=("$3"); P+=("$4")
}

T=com.apple.AppleMultitouchTrackpad
BT=com.apple.driver.AppleBluetoothMultitouch.trackpad
G=NSGlobalDomain

sec="Mouse & trackpad"
add "$sec" "Tap to click" logout \
  "u $T Clicking bool true;u $BT Clicking bool true;h $G com.apple.mouse.tapBehavior int 1"
add "$sec" "Three-finger drag (swipes move to four fingers)" logout \
  "u $T TrackpadThreeFingerDrag bool true;u $BT TrackpadThreeFingerDrag bool true;u $T TrackpadThreeFingerHorizSwipeGesture int 0;u $BT TrackpadThreeFingerHorizSwipeGesture int 0;u $T TrackpadThreeFingerVertSwipeGesture int 0;u $BT TrackpadThreeFingerVertSwipeGesture int 0"
add "$sec" "Turn off natural scrolling (wheel down = page down)" logout \
  "u $G com.apple.swipescrolldirection bool false"
add "$sec" "Mouse: no pointer acceleration" logout \
  "u $G com.apple.mouse.linear bool true"
add "$sec" "Mouse: faster pointer speed" logout \
  "u $G com.apple.mouse.scaling float 2.5"
add "$sec" "Trackpad: faster pointer speed" logout \
  "u $G com.apple.trackpad.scaling float 2"
add "$sec" "Magic Mouse: right side is right-click" logout \
  "u com.apple.driver.AppleBluetoothMultitouch.mouse MouseButtonMode string TwoButton;u com.apple.AppleMultitouchMouse MouseButtonMode string TwoButton"

sec="Dock"
add "$sec" "Auto-hide the Dock" dock "u com.apple.dock autohide bool true"
add "$sec" "Dock appears instantly (no delay, fast slide)" dock \
  "u com.apple.dock autohide-delay float 0;u com.apple.dock autohide-time-modifier float 0.5"
add "$sec" "Hide recent apps in the Dock" dock "u com.apple.dock show-recents bool false"
add "$sec" "Show only open apps (hides pinned apps)" dock "u com.apple.dock static-only bool true"
add "$sec" "Smaller icons (36 px)" dock "u com.apple.dock tilesize int 36"
add "$sec" "Magnify icons on hover" dock "u com.apple.dock magnification bool true"
add "$sec" "Dock on the left" dock "u com.apple.dock orientation string left"
add "$sec" "Minimise windows into their app icon" dock "u com.apple.dock minimize-to-application bool true"
add "$sec" "Scale minimise effect (faster than Genie)" dock "u com.apple.dock mineffect string scale"
add "$sec" "Dim the icons of hidden apps" dock "u com.apple.dock showhidden bool true"
add "$sec" "Don't reorder Spaces by recent use" dock "u com.apple.dock mru-spaces bool false"
add "$sec" "No action on bottom-right hot corner (Quick Note)" dock "u com.apple.dock wvous-br-corner int 1"

sec="Desktop & windows"
add "$sec" "Clicking the wallpaper doesn't hide all windows" logout \
  "u com.apple.WindowManager EnableStandardClickToShowDesktop bool false"
add "$sec" "Tiled windows without gaps" logout \
  "u com.apple.WindowManager EnableTiledWindowMargins bool false"
add "$sec" "Drag windows from anywhere with Ctrl+Cmd" app "u $G NSWindowShouldDragOnGesture bool true"
add "$sec" "Always show scroll bars" app "u $G AppleShowScrollBars string Always"
add "$sec" "Don't reopen windows when an app relaunches" app "u $G NSQuitAlwaysKeepsWindows bool false"

sec="Finder"
F=com.apple.finder
add "$sec" "Show all file extensions" finder "u $G AppleShowAllExtensions bool true"
add "$sec" "Show hidden files" finder "u $F AppleShowAllFiles bool true"
add "$sec" "Show path bar" finder "u $F ShowPathbar bool true"
add "$sec" "Show status bar" finder "u $F ShowStatusBar bool true"
add "$sec" "Full path in the window title" finder "u $F _FXShowPosixPathInTitle bool true"
add "$sec" "Folders on top when sorting" finder "u $F _FXSortFoldersFirst bool true"
add "$sec" "List view by default" finder "u $F FXPreferredViewStyle string Nlsv"
add "$sec" "Search the current folder by default" finder "u $F FXDefaultSearchScope string SCcf"
add "$sec" "No warning when changing a file extension" finder "u $F FXEnableExtensionChangeWarning bool false"
add "$sec" "New windows open your home folder" finder \
  "u $F NewWindowTarget string PfHm;u $F NewWindowTargetPath string file://$HOME/"
add "$sec" "Empty Trash items after 30 days" finder "u $F FXRemoveOldTrashItems bool true"
add "$sec" "No .DS_Store files on network and USB drives" finder \
  "u com.apple.desktopservices DSDontWriteNetworkStores bool true;u com.apple.desktopservices DSDontWriteUSBStores bool true"
add "$sec" "Show the ~/Library folder" finder "fn:library"

sec="Keyboard & typing"
kbui=2; [[ "$macos_major" -lt 14 ]] && kbui=3
add "$sec" "Fast key repeat" logout "u $G KeyRepeat int 2;u $G InitialKeyRepeat int 15"
add "$sec" "Holding a key repeats it (no accent popup for é à ñ)" app "u $G ApplePressAndHoldEnabled bool false"
add "$sec" "F1-F12 act as standard function keys" logout "u $G com.apple.keyboard.fnState bool true"
add "$sec" "Tab moves between all controls" app "u $G AppleKeyboardUIMode int $kbui"
add "$sec" "No autocorrect" app \
  "u $G NSAutomaticSpellingCorrectionEnabled bool false;u $G WebAutomaticSpellingCorrectionEnabled bool false"
add "$sec" "No automatic capitals" app "u $G NSAutomaticCapitalizationEnabled bool false"
add "$sec" "No smart quotes or dashes" app \
  "u $G NSAutomaticQuoteSubstitutionEnabled bool false;u $G NSAutomaticDashSubstitutionEnabled bool false"
add "$sec" "No full stop on double space" app "u $G NSAutomaticPeriodSubstitutionEnabled bool false"

sec="Screenshots"
add "$sec" "Save screenshots to ~/Pictures/Screenshots" ui "fn:shots"
add "$sec" "No window shadow on window captures" ui "u com.apple.screencapture disable-shadow bool true"
add "$sec" "No floating thumbnail after a capture" ui "u com.apple.screencapture show-thumbnail bool false"

sec="Menu bar"
add "$sec" "Show battery percentage" cc "h com.apple.controlcenter BatteryShowPercentage bool true"
add "$sec" "Clock shows seconds" cc "u com.apple.menuextra.clock ShowSeconds bool true"
add "$sec" "Auto-hide the menu bar" logout "u $G _HIHideMenuBar bool true"

sec="Dialogs & apps"
add "$sec" "Expanded Save and Print dialogs" app \
  "u $G NSNavPanelExpandedStateForSaveMode bool true;u $G NSNavPanelExpandedStateForSaveMode2 bool true;u $G PMPrintingExpandedStateForPrint bool true;u $G PMPrintingExpandedStateForPrint2 bool true"
add "$sec" "Save new documents to disk, not iCloud" app "u $G NSDocumentSaveNewDocumentsToCloud bool false"
add "$sec" "TextEdit opens plain text documents" app "u com.apple.TextEdit RichText bool false"

N=${#L[@]}

# ---------------------------------------------------------------------------
# Custom settings (fn:NAME)
# ---------------------------------------------------------------------------
library_state() { [[ "$(stat -f %Sf "$HOME/Library" 2>/dev/null)" != *hidden* ]]; }
library_on()    { run chflags nohidden "$HOME/Library"; }
library_off()   { run chflags hidden "$HOME/Library"; }

SHOTS="$HOME/Pictures/Screenshots"
shots_state() { [[ "$(defaults read com.apple.screencapture location 2>/dev/null)" == "$SHOTS" ]]; }
shots_on()    { run mkdir -p "$SHOTS"; run defaults write com.apple.screencapture location -string "$SHOTS"; }
shots_off()   { run defaults delete com.apple.screencapture location; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run a command, or only print it under --dry-run.
run() {
  if [[ "$dry" == true ]]; then
    printf '+'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# d SCOPE ARGS... -> defaults [-currentHost] ARGS...
d() {
  local scope=$1; shift
  if [[ "$scope" == h ]]; then defaults -currentHost "$@"; else defaults "$@"; fi
}

# Is setting $1 currently on? Checks the first spec only.
is_on() {
  local spec=${P[$1]%%;*} scope domain key type value got
  if [[ "$spec" == fn:* ]]; then "${spec#fn:}_state"; return; fi
  read -r scope domain key type value <<<"$spec"
  got=$(d "$scope" read "$domain" "$key" 2>/dev/null) || return 1
  case "$type" in
    bool) [[ "$value" == true ]] && value=1 || value=0; [[ "$got" == "$value" ]] ;;
    int|float) awk -v a="$got" -v b="$value" 'BEGIN { exit !(a + 0 == b + 0) }' ;;
    *) [[ "$got" == "$value" ]] ;;
  esac
}

# set_setting INDEX on|off
set_setting() {
  local i=$1 want=$2 spec scope domain key type value rest
  rest=${P[$i]}
  if [[ "$rest" == fn:* ]]; then "${rest#fn:}_$want"; return; fi
  while [[ -n "$rest" ]]; do
    spec=${rest%%;*}
    [[ "$rest" == *";"* ]] && rest=${rest#*;} || rest=
    read -r scope domain key type value <<<"$spec"
    local pre=(defaults); [[ "$scope" == h ]] && pre=(defaults -currentHost)
    if [[ "$want" == on ]]; then
      run "${pre[@]}" write "$domain" "$key" "-$type" "$value"
    else
      # A key that is already unset is fine; don't fail on it.
      if [[ "$dry" == true ]] || d "$scope" read "$domain" "$key" >/dev/null 2>&1; then
        run "${pre[@]}" delete "$domain" "$key"
      fi
    fi
  done
}

# Current state of every setting (1/0), cached; refreshed after apply.
STATE=() PEND=()
refresh_state() {
  local i
  for ((i = 0; i < N; i++)); do
    if is_on "$i"; then STATE[i]=1; else STATE[i]=0; fi
    PEND[i]=
  done
}

pending_count() {
  local i c=0
  for ((i = 0; i < N; i++)); do [[ -n "${PEND[$i]}" ]] && c=$((c + 1)); done
  echo "$c"
}

clear_screen() { [[ -t 1 ]] && printf '\033[H\033[2J'; }

# Items (indexes into the table) of a section, space separated.
section_items() {
  local i out=
  for ((i = 0; i < N; i++)); do [[ "${S[$i]}" == "$1" ]] && out="$out $i"; done
  echo "$out"
}

# "[x] " / "[ ]*" for item $1, showing the queued value with a * marker.
box() {
  local i=$1 v=${STATE[$1]} mark=" "
  if [[ -n "${PEND[$i]}" ]]; then mark="*"; [[ "${PEND[$i]}" == on ]] && v=1 || v=0; fi
  [[ "$v" == 1 ]] && printf '[x]%s' "$mark" || printf '[ ]%s' "$mark"
}

# Queue a toggle for item $1 (toggling back cancels it).
toggle() {
  local i=$1
  if [[ -n "${PEND[$i]}" ]]; then PEND[i]=
  elif [[ "${STATE[$i]}" == 1 ]]; then PEND[i]=off
  else PEND[i]=on
  fi
}

apply_pending() {
  local i c effects=" " backup domains=" " spec rest scope domain
  c=$(pending_count)
  if [[ "$c" -eq 0 ]]; then echo "Nothing to apply."; return; fi

  # Back up every preference domain about to change.
  backup="$HOME/Library/Application Support/mac-settings/backup-$(date +%Y%m%d-%H%M%S)"
  [[ "$dry" == true ]] || mkdir -p "$backup"
  for ((i = 0; i < N; i++)); do
    [[ -z "${PEND[$i]}" || "${P[$i]}" == fn:* ]] && continue
    rest=${P[$i]}
    while [[ -n "$rest" ]]; do
      spec=${rest%%;*}
      [[ "$rest" == *";"* ]] && rest=${rest#*;} || rest=
      read -r scope domain _ <<<"$spec"
      [[ "$domains" == *" $scope:$domain "* ]] && continue
      domains="$domains$scope:$domain "
      [[ "$dry" == true ]] && continue
      d "$scope" export "$domain" "$backup/$scope-$domain.plist" 2>/dev/null || true
    done
  done

  echo
  for ((i = 0; i < N; i++)); do
    [[ -z "${PEND[$i]}" ]] && continue
    echo "${PEND[$i]}: ${L[$i]}"
    set_setting "$i" "${PEND[$i]}"
    [[ "$effects" == *" ${E[$i]} "* ]] || effects="$effects${E[$i]} "
  done

  [[ "$effects" == *" dock "* ]] && run killall Dock
  [[ "$effects" == *" finder "* ]] && run killall Finder
  [[ "$effects" == *" ui "* ]] && run killall SystemUIServer
  [[ "$effects" == *" cc "* ]] && run killall ControlCenter

  echo
  if [[ "$dry" == true ]]; then
    echo "Dry run: nothing was changed."
  else
    echo "Applied $c change(s). Backup of the old preferences: $backup"
  fi
  [[ "$effects" == *" app "* ]] && echo "Quit and reopen apps to pick up the text/window changes."
  [[ "$effects" == *" logout "* ]] && echo "Log out and back in (Apple menu > Log Out) for mouse/trackpad/keyboard changes."
  refresh_state
}

list_all() {
  local s i
  for s in "${SECTIONS[@]}"; do
    echo "$s"
    for i in $(section_items "$s"); do
      printf '  %s %s\n' "$(box "$i")" "${L[$i]}"
    done
  done
}

section_menu() {
  local s=$1 items i n ans tok
  read -r -a items <<<"$(section_items "$s")"
  while true; do
    clear_screen
    echo "$s"
    echo
    n=1
    for i in "${items[@]}"; do
      printf '  %2d %s %s\n' "$n" "$(box "$i")" "${L[$i]}"
      n=$((n + 1))
    done
    echo
    echo "  [x] on  [ ] off  * = queued, not applied yet ($(pending_count) queued)"
    echo "  Type numbers to toggle (e.g. 1 3), a = apply, b = back"
    printf '> '
    read -r ans || exit 0
    case "$ans" in
      b|B|"") return ;;
      a|A) apply_pending; printf 'Press Enter...'; read -r _ ;;
      *)
        for tok in ${ans//,/ }; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && ((tok >= 1 && tok <= ${#items[@]})); then
            toggle "${items[$((tok - 1))]}"
          fi
        done
        ;;
    esac
  done
}

main_menu() {
  local s n ans on total i
  while true; do
    clear_screen
    echo "Mac settings - macOS $macos_version (built-in tools only)$([[ "$dry" == true ]] && echo '  [DRY RUN]')"
    echo
    n=1
    for s in "${SECTIONS[@]}"; do
      on=0 total=0
      for i in $(section_items "$s"); do
        total=$((total + 1)); [[ "${STATE[$i]}" == 1 ]] && on=$((on + 1))
      done
      printf '  %d  %-22s %2d/%d on\n' "$n" "$s" "$on" "$total"
      n=$((n + 1))
    done
    echo
    echo "  $(pending_count) change(s) queued"
    echo "  Pick a section, a = apply, l = list all, q = quit"
    printf '> '
    read -r ans || exit 0
    case "$ans" in
      q|Q)
        if [[ "$(pending_count)" -gt 0 ]]; then
          printf 'Discard %s queued change(s)? [y/N] ' "$(pending_count)"
          read -r ans || exit 0
          [[ "$ans" == y || "$ans" == Y ]] || continue
        fi
        exit 0
        ;;
      a|A) apply_pending; printf 'Press Enter...'; read -r _ ;;
      l|L) clear_screen; list_all; printf '\nPress Enter...'; read -r _ ;;
      *)
        if [[ "$ans" =~ ^[0-9]+$ ]] && ((ans >= 1 && ans <= ${#SECTIONS[@]})); then
          section_menu "${SECTIONS[$((ans - 1))]}"
        fi
        ;;
    esac
  done
}

refresh_state
if [[ "$mode" == list ]]; then
  list_all
  exit 0
fi
main_menu
