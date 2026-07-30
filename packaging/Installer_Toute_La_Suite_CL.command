#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS_ROOT="$SCRIPT_DIR/Composants"
INTEGRITY_MANIFEST="$SCRIPT_DIR/COMPONENTS_SHA256.txt"
APPLICATIONS_SOURCE="$COMPONENTS_ROOT/Applications"
LIVE_CURRENT_SOURCE="$COMPONENTS_ROOT/Ableton Live 11-12"
LIVE10_SOURCE_ROOT="$COMPONENTS_ROOT/Ableton Live 10"
MIDI_TOOLS_SOURCE="$COMPONENTS_ROOT/Outils réseau MIDI"
INSTALL_HOME="${CL_SUITE_INSTALL_HOME:-$HOME}"
USER_APPS="$INSTALL_HOME/Applications"
SUPPORT_DIR="$INSTALL_HOME/Library/Application Support/CL Audio Controller"
INSTALL_MANIFEST="$SUPPORT_DIR/CL_Suite_install_manifest.tsv"
STAMP="$(date '+%Y-%m-%d_%H%M%S')"
WORK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/CL_Suite_Installer_XXXXXX")"
MANIFEST_UPDATES="$WORK_DIR/manifest_updates.tsv"
REPORT="$WORK_DIR/rapport.txt"
INSTALLED_LIST="$WORK_DIR/installed.tsv"
LIVE_LIST="$WORK_DIR/live.tsv"
WARNINGS="$WORK_DIR/warnings.txt"

: > "$MANIFEST_UPDATES"; : > "$INSTALLED_LIST"; : > "$LIVE_LIST"; : > "$WARNINGS"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

say() { printf '%s\n' "$*" | tee -a "$REPORT"; }
warn() { printf 'AVERTISSEMENT : %s\n' "$*" | tee -a "$REPORT" "$WARNINGS" >&2; }
fail() { printf '\nERREUR : %s\n' "$1" | tee -a "$REPORT" >&2; save_report || true; exit 1; }
require_source() { [[ -e "$1" ]] || fail "élément absent du kit : $1"; }

save_report() {
  local desktop="$INSTALL_HOME/Desktop"
  local destination
  mkdir -p "$SUPPORT_DIR"
  destination="$SUPPORT_DIR/Rapport_installation_${STAMP}.txt"
  cp "$REPORT" "$destination" 2>/dev/null || true
  if [[ -d "$desktop" ]]; then cp "$REPORT" "$desktop/Rapport installation Suite CL ${STAMP}.txt" 2>/dev/null || true; fi
}

choose_folder() {
  /usr/bin/osascript <<'APPLESCRIPT'
try
  set selectedFolder to choose folder with prompt "Sélectionnez le dossier racine « User Library » d’Ableton Live"
  return POSIX path of selectedFolder
on error number -128
  return ""
end try
APPLESCRIPT
}

is_user_library() {
  local p="$1"
  [[ -d "$p" ]] || return 1
  case "$(basename "$p")" in
    "User Library") return 0 ;;
  esac
  [[ -d "$p/Presets" || -d "$p/Remote Scripts" ]] && return 0
  return 1
}

detect_live() {
  local root app version plist
  if [[ -n "${CL_SUITE_LIVE_APPS:-}" ]]; then
    printf '%s\n' "$CL_SUITE_LIVE_APPS" | tr ':' '\n' | while IFS= read -r app; do
      [[ -d "$app" ]] || continue
      version=""
      plist="$app/Contents/Info.plist"
      if [[ -f "$plist" ]]; then
        version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
      fi
      [[ -n "$version" ]] || version="$(basename "$app" | sed -E 's/.*Live ([0-9]+).*/\1/')"
      printf '%s\t%s\n' "$version" "$app" >> "$LIVE_LIST"
    done
  else
    for root in /Applications "$INSTALL_HOME/Applications"; do
      [[ -d "$root" ]] || continue
      for app in "$root"/Ableton\ Live\ 10*.app "$root"/Ableton\ Live\ 11*.app "$root"/Ableton\ Live\ 12*.app; do
        [[ -d "$app" ]] || continue
        version=""
        plist="$app/Contents/Info.plist"
        if [[ -f "$plist" ]]; then
          version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
        fi
        [[ -n "$version" ]] || version="$(basename "$app" | sed -E 's/.*Live ([0-9]+).*/\1/')"
        printf '%s\t%s\n' "$version" "$app" >> "$LIVE_LIST"
      done
    done
  fi
  if [[ -s "$LIVE_LIST" ]]; then awk -F '\t' '!seen[$2]++' "$LIVE_LIST" > "$LIVE_LIST.tmp" && mv "$LIVE_LIST.tmp" "$LIVE_LIST"; fi
}

live_major() { printf '%s' "$1" | sed -E 's/^([0-9]+).*/\1/'; }

check_max_for_live() {
  local app="$1" name info
  [[ "${CL_SUITE_ASSUME_M4L:-0}" == "1" ]] && return 0
  name="$(basename "$app")"
  info="$app/Contents/Info.plist"
  if printf '%s' "$name" | grep -qi 'Suite'; then return 0; fi
  if [[ -d "$app/Contents/App-Resources/Max" || -d "$app/Contents/Resources/Max" ]]; then return 0; fi
  if /usr/bin/find "$app/Contents" -maxdepth 5 \( -iname 'Max for Live*' -o -iname 'MaxAudioEffect.amxd' -o -iname 'MaxMidiEffect.amxd' \) -print -quit 2>/dev/null | grep -q .; then return 0; fi
  if [[ -f "$info" ]] && /usr/libexec/PlistBuddy -c 'Print' "$info" 2>/dev/null | grep -qi 'Max for Live'; then return 0; fi
  return 1
}

resolve_user_library() {
  local candidate pref extracted
  if [[ -n "${CL_SUITE_USER_LIBRARY:-}" ]]; then
    candidate="${CL_SUITE_USER_LIBRARY%/}"
    is_user_library "$candidate" || fail "la User Library imposée n'est pas valide : $candidate"
    printf '%s' "$candidate"; return 0
  fi
  candidate="$INSTALL_HOME/Music/Ableton/User Library"
  if is_user_library "$candidate"; then printf '%s' "$candidate"; return 0; fi
  for pref in "$INSTALL_HOME"/Library/Preferences/Ableton/Live\ */Preferences/Preferences.cfg; do
    [[ -f "$pref" ]] || continue
    extracted="$(strings "$pref" 2>/dev/null | grep -E '/.*User Library/?$' | tail -1 || true)"
    if [[ -n "$extracted" ]] && is_user_library "$extracted"; then printf '%s' "${extracted%/}"; return 0; fi
  done
  if [[ "${CL_SUITE_NONINTERACTIVE:-0}" == "1" ]]; then
    mkdir -p "$candidate/Presets" "$candidate/Remote Scripts"
    printf '%s' "$candidate"; return 0
  fi
  candidate="$(choose_folder)"
  [[ -n "$candidate" ]] || fail "aucune User Library sélectionnée"
  candidate="${candidate%/}"
  is_user_library "$candidate" || fail "le dossier sélectionné ne ressemble pas à une User Library Ableton : $candidate"
  printf '%s' "$candidate"
}

backup_existing() {
  local target="$1" backup
  if [[ -e "$target" || -L "$target" ]]; then
    backup="${target}.sauvegarde_${STAMP}"
    [[ ! -e "$backup" ]] || fail "sauvegarde déjà existante : $backup"
    say "  Sauvegarde : $backup"
    mv "$target" "$backup"
  fi
}

tree_digest() {
  local p="$1"
  if [[ -f "$p" ]]; then shasum -a 256 "$p" | awk '{print $1}'; return; fi
  (cd "$p" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null) | shasum -a 256 | awk '{print $1}'
}

verify_copy() {
  local source="$1" target="$2" sd td
  [[ -e "$target" ]] || return 1
  sd="$(tree_digest "$source")"; td="$(tree_digest "$target")"
  [[ "$sd" == "$td" ]]
}

install_item() {
  local source="$1" target="$2" label="$3" component="$4"
  require_source "$source"
  say ""; say "$label"
  backup_existing "$target"
  mkdir -p "$(dirname "$target")"
  ditto "$source" "$target"
  if verify_copy "$source" "$target"; then
    say "  ✓ Installé et vérifié : $target"
    printf '%s\t%s\tOK\n' "$label" "$target" >> "$INSTALLED_LIST"
  else
    printf '%s\t%s\tECHEC\n' "$label" "$target" >> "$INSTALLED_LIST"
    fail "la copie n'est pas conforme : $target"
  fi
  printf '%s\t%s\t%s\n' "$component" "$target" "$STAMP" >> "$MANIFEST_UPDATES"
}

write_install_manifest() {
  local combined="$WORK_DIR/manifest_combined.tsv"
  mkdir -p "$SUPPORT_DIR"; chmod 700 "$SUPPORT_DIR"
  if [[ -f "$INSTALL_MANIFEST" && ! -L "$INSTALL_MANIFEST" ]]; then cat "$INSTALL_MANIFEST" > "$combined"; else : > "$combined"; fi
  cat "$MANIFEST_UPDATES" >> "$combined"
  awk -F '\t' 'NF == 3 { latest[$1 FS $2] = $0 } END { for (key in latest) print latest[key] }' "$combined" | LC_ALL=C sort > "$INSTALL_MANIFEST.tmp"
  chmod 600 "$INSTALL_MANIFEST.tmp"; mv "$INSTALL_MANIFEST.tmp" "$INSTALL_MANIFEST"
}

verify_selected_components() {
  local selected="$WORK_DIR/selected_sha256.txt" line rel
  : > "$selected"
  while IFS= read -r line; do
    rel="${line#*  }"
    case "$rel" in
      "Composants/Applications/CL Audio Controller.app/"*) [[ "$INSTALL_REMOTE" == 1 || "$INSTALL_CONTROLLER" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Ableton Live 11-12/Remote Scripts/AbletonOSC/"*|"Composants/Ableton Live 11-12/Max for Live/CL Audio Controller - Remote/"*) [[ "$INSTALL_REMOTE" == 1 || "$INSTALL_ABLETON_READER" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Applications/CL MIDI RTP Agent.app/"*|"Composants/Applications/CL MIDI RTP Simulator.app/"*) [[ "$INSTALL_ABLETON_READER" == 1 || "$INSTALL_MIDI_RECEIVER" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Applications/Arrangement Builder Live.app/"*|"Composants/Ableton Live 11-12/Remote Scripts/CL_Arrangement_Builder_Live/"*) [[ "$INSTALL_BUILDER" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Ableton Live 11-12/Max for Live/Paradis Latin AutoScene/"*) [[ "$INSTALL_AUTOSCENE" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Ableton Live 10/Max for Live/Paradis Latin AutoScene - Live 10/"*) [[ "$INSTALL_AUTOSCENE_LIVE10" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Applications/CL MIDI Network Assistant.app/"*|"Composants/Outils réseau MIDI/"*) [[ "$INSTALL_MIDI_CONSOLE" == 1 || "$INSTALL_CONTROLLER" == 1 ]] && echo "$line" >> "$selected" ;;
      "Composants/Ableton Live 11-12/Max for Live/CL MIDI Console Monitor/"*) [[ "$INSTALL_MIDI_CONSOLE" == 1 ]] && echo "$line" >> "$selected" ;;
    esac
  done < "$INTEGRITY_MANIFEST"
  [[ -s "$selected" ]] || fail "aucune empreinte trouvée pour les composants sélectionnés"
  (cd "$SCRIPT_DIR" && shasum -a 256 -c "$selected" >/dev/null) || fail "le contrôle d'intégrité du kit a échoué"
}

say "============================================================"
say " INSTALLATEUR INTELLIGENT — SUITE CL"
say "============================================================"
say "Fermez complètement Ableton Live avant de continuer."
say "Aucun mot de passe administrateur n'est nécessaire."

if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" ]]; then
  read -r -p "Continuer ? (o/n) " answer
  case "$answer" in o|O|oui|OUI|y|Y|yes|YES) ;; *) exit 0;; esac
fi

detect_live
[[ -s "$LIVE_LIST" ]] || fail "aucune installation d'Ableton Live 10, 11 ou 12 n'a été détectée"
say ""; say "Ableton Live détecté :"
HAS10=0; HAS_CURRENT=0; M4L_OK=0
while IFS=$'\t' read -r version app; do
  major="$(live_major "$version")"
  case "$major" in 10) HAS10=1 ;; 11|12) HAS_CURRENT=1 ;; *) continue ;; esac
  if check_max_for_live "$app"; then
    say "  ✓ Live $version — Max for Live détecté — $app"; M4L_OK=1
  else
    say "  ! Live $version — Max for Live non confirmé — $app"
  fi
done < "$LIVE_LIST"
if [[ "$M4L_OK" != 1 ]]; then
  if [[ "${CL_SUITE_NONINTERACTIVE:-0}" == "1" ]]; then fail "Max for Live n'a pas pu être confirmé"; fi
  read -r -p "Max for Live est-il bien disponible dans votre licence Live ? (o/n) " answer
  [[ "$answer" =~ ^([oOyY]|oui|OUI|yes|YES)$ ]] || fail "Max for Live est nécessaire"
  warn "Max for Live confirmé manuellement par l'utilisateur."
fi

ABLETON_LIBRARY="$(resolve_user_library)"
REMOTE_SCRIPTS="$ABLETON_LIBRARY/Remote Scripts"
M4L_REMOTE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Remote"
M4L_AUTOSCENE_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - AutoScene"
M4L_LIVE10_TARGET="$ABLETON_LIBRARY/Presets/Audio Effects/Max Audio Effect/CL Audio Controller - Live 10"
M4L_MIDI_CONSOLE_TARGET="$ABLETON_LIBRARY/Presets/MIDI Effects/Max MIDI Effect/CL MIDI Console Monitor"
MIDI_TOOLS_TARGET="$INSTALL_HOME/Library/Application Support/CL MIDI Console/Network Tools"
say ""; say "User Library retenue : $ABLETON_LIBRARY"

INSTALL_REMOTE=0; INSTALL_CONTROLLER=0; INSTALL_ABLETON_READER=0; INSTALL_BUILDER=0; INSTALL_AUTOSCENE=0; INSTALL_AUTOSCENE_LIVE10=0; INSTALL_MIDI_CONSOLE=0; INSTALL_MIDI_RECEIVER=0
CHOICE="${CL_SUITE_COMPONENTS:-}"
if [[ -z "$CHOICE" ]]; then
  echo; echo "Composants à installer :"; echo "  1 — Suite complète"; echo "  2 — Télécommande CL Audio uniquement"; echo "  3 — Arrangement Builder uniquement"; echo "  4 — AutoScene uniquement"; echo "  5 — CL MIDI Console uniquement"; echo "  6 — Annuler"
  read -r -p "Votre choix : " CHOICE
fi
case "$CHOICE" in
  1|all|complete) INSTALL_CONTROLLER=1; INSTALL_ABLETON_READER=1; INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1; INSTALL_MIDI_CONSOLE=1 ;;
  2|remote) INSTALL_REMOTE=1 ;;
  controller|show-control) INSTALL_CONTROLLER=1 ;;
  ableton-reader|reader) INSTALL_ABLETON_READER=1; INSTALL_BUILDER=1; INSTALL_AUTOSCENE=1 ;;
  3|builder) INSTALL_BUILDER=1 ;;
  4|autoscene) INSTALL_AUTOSCENE=1 ;;
  5|midi-console) INSTALL_MIDI_CONSOLE=1 ;;
  midi-receiver|receiver|simulator) INSTALL_MIDI_RECEIVER=1 ;;
  6|cancel) exit 0 ;;
  *)
    normalized=",$CHOICE,"
    [[ "$normalized" == *,remote,* ]] && INSTALL_REMOTE=1
    [[ "$normalized" == *,controller,* ]] && INSTALL_CONTROLLER=1
    [[ "$normalized" == *,ableton-reader,* ]] && INSTALL_ABLETON_READER=1
    [[ "$normalized" == *,builder,* ]] && INSTALL_BUILDER=1
    [[ "$normalized" == *,autoscene,* ]] && INSTALL_AUTOSCENE=1
    [[ "$normalized" == *,midi-console,* ]] && INSTALL_MIDI_CONSOLE=1
    [[ "$normalized" == *,midi-receiver,* ]] && INSTALL_MIDI_RECEIVER=1
    ;;
esac

if [[ "$INSTALL_AUTOSCENE" == 1 ]]; then
  [[ "$HAS_CURRENT" == 1 ]] || INSTALL_AUTOSCENE=0
  [[ "$HAS10" == 1 ]] && INSTALL_AUTOSCENE_LIVE10=1
fi
if [[ "$HAS_CURRENT" != 1 && ( "$INSTALL_REMOTE" == 1 || "$INSTALL_CONTROLLER" == 1 || "$INSTALL_ABLETON_READER" == 1 || "$INSTALL_BUILDER" == 1 || "$INSTALL_MIDI_CONSOLE" == 1 ) ]]; then
  fail "les composants sélectionnés nécessitent Live 11 ou Live 12 ; seul Live 10 a été détecté"
fi

say ""; say "Vérification de l'intégrité du kit…"
verify_selected_components
mkdir -p "$USER_APPS" "$REMOTE_SCRIPTS" "$ABLETON_LIBRARY/Presets"

[[ "$INSTALL_REMOTE" == 1 || "$INSTALL_CONTROLLER" == 1 ]] && install_item "$APPLICATIONS_SOURCE/CL Audio Controller.app" "$USER_APPS/CL Audio Controller.app" "Télécommande — CL Audio Controller" "controller"
if [[ "$INSTALL_CONTROLLER" == 1 ]]; then
  install_item "$MIDI_TOOLS_SOURCE" "$MIDI_TOOLS_TARGET" "Télécommande — Outils diagnostic réseau MIDI" "controller"
  install_item "$APPLICATIONS_SOURCE/CL MIDI Network Assistant.app" "$USER_APPS/CL MIDI Network Assistant.app" "Télécommande — Assistant réseau MIDI" "controller"
fi
if [[ "$INSTALL_REMOTE" == 1 || "$INSTALL_ABLETON_READER" == 1 ]]; then
  install_item "$LIVE_CURRENT_SOURCE/Remote Scripts/AbletonOSC" "$REMOTE_SCRIPTS/AbletonOSC" "Ableton Lecteur — AbletonOSC CL" "ableton-reader"
  install_item "$LIVE_CURRENT_SOURCE/Max for Live/CL Audio Controller - Remote" "$M4L_REMOTE_TARGET" "Ableton Lecteur — LTC et X-Fader" "ableton-reader"
fi
if [[ "$INSTALL_ABLETON_READER" == 1 ]]; then
  install_item "$APPLICATIONS_SOURCE/CL MIDI RTP Agent.app" "$USER_APPS/CL MIDI RTP Agent.app" "Ableton Lecteur — Agent RTP léger" "ableton-reader"
  install_item "$APPLICATIONS_SOURCE/CL MIDI RTP Simulator.app" "$USER_APPS/CL MIDI RTP Simulator.app" "Ableton Lecteur — Simulateur RTP" "ableton-reader"
fi
if [[ "$INSTALL_BUILDER" == 1 ]]; then
  install_item "$APPLICATIONS_SOURCE/Arrangement Builder Live.app" "$USER_APPS/Arrangement Builder Live.app" "Builder — Application" "builder"
  install_item "$LIVE_CURRENT_SOURCE/Remote Scripts/CL_Arrangement_Builder_Live" "$REMOTE_SCRIPTS/CL_Arrangement_Builder_Live" "Builder — Remote Script" "builder"
fi
[[ "$INSTALL_AUTOSCENE" == 1 ]] && install_item "$LIVE_CURRENT_SOURCE/Max for Live/Paradis Latin AutoScene" "$M4L_AUTOSCENE_TARGET" "AutoScene — Version Live 11/12" "autoscene"
[[ "$INSTALL_AUTOSCENE_LIVE10" == 1 ]] && install_item "$LIVE10_SOURCE_ROOT/Max for Live/Paradis Latin AutoScene - Live 10" "$M4L_LIVE10_TARGET" "AutoScene — Version Live 10" "autoscene-live10"
if [[ "$INSTALL_MIDI_CONSOLE" == 1 ]]; then
  install_item "$LIVE_CURRENT_SOURCE/Max for Live/CL MIDI Console Monitor" "$M4L_MIDI_CONSOLE_TARGET" "MIDI Console — Périphérique Max for Live" "midi-console"
  [[ "$INSTALL_CONTROLLER" != 1 ]] && install_item "$MIDI_TOOLS_SOURCE" "$MIDI_TOOLS_TARGET" "MIDI Console — Outils réseau" "midi-console"
  [[ "$INSTALL_CONTROLLER" != 1 ]] && install_item "$APPLICATIONS_SOURCE/CL MIDI Network Assistant.app" "$USER_APPS/CL MIDI Network Assistant.app" "MIDI Console — Assistant réseau" "midi-console"
fi
[[ "$INSTALL_MIDI_RECEIVER" == 1 ]] && install_item "$APPLICATIONS_SOURCE/CL MIDI RTP Simulator.app" "$USER_APPS/CL MIDI RTP Simulator.app" "RTP — Simulateur de console" "midi-receiver"

write_install_manifest
say ""; say "============================================================"; say " INSTALLATION TERMINÉE ET VÉRIFIÉE"; say "============================================================"
say "Versions Live détectées :"
while IFS=$'\t' read -r version app; do say "  • Live $version : $app"; done < "$LIVE_LIST"
say "User Library : $ABLETON_LIBRARY"
say "Composants installés :"
while IFS=$'\t' read -r label target status; do say "  ✓ $label"; say "    → $target"; done < "$INSTALLED_LIST"
say "Manifeste : $INSTALL_MANIFEST"
[[ -s "$WARNINGS" ]] && { say "Avertissements :"; cat "$WARNINGS" | tee -a "$REPORT"; }
save_report
say "Rapport copié dans : $SUPPORT_DIR"
say "Relancez Ableton Live. Les périphériques se trouvent dans la User Library indiquée ci-dessus."
if [[ "${CL_SUITE_NONINTERACTIVE:-0}" != "1" ]]; then
  /usr/bin/open "$ABLETON_LIBRARY" >/dev/null 2>&1 || true
  read -r -p "Appuyez sur Entrée pour fermer cette fenêtre." _
fi
