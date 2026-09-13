"""Bridge V1 de rendu WAV depuis l'Arrangement Ableton existant.

La resolution des zones est pure. L'execution macOS est isolee derriere un
callable afin de rester testable sans GUI et sans toucher au transport Live.
"""

from __future__ import annotations

import json
from contextlib import nullcontext
import os
import re
import shutil
import subprocess
import threading
import time
import tempfile
import urllib.error
import urllib.request
import uuid
import wave
from pathlib import Path
from typing import Any, Callable, Iterable



OFFLINE_UNAVAILABLE = "OFFLINE_UNAVAILABLE"
OFFLINE_FAILED = "OFFLINE_FAILED"
OFFLINE_SUCCESS = "success"


class OfflineExportError(RuntimeError):
    pass


def _positive_float(value: Any, name: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise OfflineExportError(f"{name} invalide") from exc
    if result < 0:
        raise OfflineExportError(f"{name} invalide")
    return result


def scene_number_from_marker(name: Any) -> int | None:
    match = re.match(r"^\s*0*(\d{1,3})(?:\s|[.\-–—:|])", str(name or ""))
    if not match:
        return None
    number = int(match.group(1))
    return number if number > 0 else None


def normalize_arrangement_markers(markers: Iterable[dict]) -> list[dict]:
    result = []
    for raw in markers or []:
        number = scene_number_from_marker(raw.get("name"))
        if number is None:
            continue
        try:
            position = _positive_float(raw.get("time"), "position Arrangement")
        except OfflineExportError:
            continue
        result.append({
            "scene_number": number,
            "name": str(raw.get("name") or "").strip(),
            "start_beats": position,
        })
    result.sort(key=lambda item: item["start_beats"])
    return result


def build_arrangement_zones(export_job: dict, markers: Iterable[dict]) -> list[dict]:
    """Resout une scene ou un medley en une seule zone de locators Live."""
    normalized = normalize_arrangement_markers(markers)
    by_number = {item["scene_number"]: item for item in normalized}
    by_position = {item["start_beats"]: index for index, item in enumerate(normalized)}
    zones = []
    for job_item in export_job.get("items") or []:
        source = job_item.get("source_item") or {}
        item_type = str(job_item.get("type") or source.get("type") or "")
        if item_type == "medley_full":
            numbers = [int(value) for value in source.get("scene_numbers") or []]
            if not numbers:
                raise OfflineExportError("medley sans scenes")
            first_number, last_number = numbers[0], numbers[-1]
        else:
            first_number = last_number = int(source.get("scene_number"))
        first = by_number.get(first_number)
        last = by_number.get(last_number)
        if first is None or last is None:
            raise OfflineExportError(
                f"locator Arrangement absent pour {first_number}-{last_number}"
            )
        last_index = by_position[last["start_beats"]]
        if last_index + 1 >= len(normalized):
            raise OfflineExportError(f"locator de fin absent apres la scene {last_number}")
        end_beats = normalized[last_index + 1]["start_beats"]
        duration_beats = end_beats - first["start_beats"]
        if duration_beats <= 0:
            raise OfflineExportError("zone Arrangement vide")
        zones.append({
            "id": job_item.get("id"),
            "type": "medley" if item_type == "medley_full" else "scene",
            "title": source.get("title") or "",
            "scene_numbers": list(range(first_number, last_number + 1)),
            "start_beats": first["start_beats"],
            "end_beats": end_beats,
            "duration_beats": duration_beats,
            "expected_duration_seconds": source.get("duration_seconds"),
            "job_item": job_item,
        })
    return zones


def beats_to_bbt(value: Any, beats_per_bar: int = 4) -> tuple[int, int, int]:
    beats = _positive_float(value, "position en beats")
    if beats_per_bar <= 0:
        raise OfflineExportError("signature invalide")
    total_sixteenths = round(beats * 4)
    bar, within_bar = divmod(total_sixteenths, beats_per_bar * 4)
    beat, sixteenth = divmod(within_bar, 4)
    return bar + 1, beat + 1, sixteenth + 1


def beats_to_length_bbt(value: Any, beats_per_bar: int = 4) -> tuple[int, int, int]:
    beats = _positive_float(value, "longueur en beats")
    if beats_per_bar <= 0:
        raise OfflineExportError("signature invalide")
    total_sixteenths = round(beats * 4)
    bars, within_bar = divmod(total_sixteenths, beats_per_bar * 4)
    whole_beats, sixteenths = divmod(within_bar, 4)
    return bars, whole_beats, sixteenths


_LIVE_EXPORT_LOCK = threading.RLock()

_OFFLINE_LIVE_LOOP_URL = os.environ.get(
    "CL_AUDIO_OFFLINE_LIVE_LOOP_URL",
    "http://127.0.0.1:5050/show-audio/offline/live-loop",
).strip()


def _bbt_start_to_live_beats(
    bbt: tuple[int, int, int],
    beats_per_bar: int = 4,
) -> float:
    bar, beat, sixteenth = (int(value) for value in bbt)

    if (
        beats_per_bar <= 0
        or bar < 1
        or beat < 1
        or beat > beats_per_bar
        or sixteenth < 1
        or sixteenth > 4
    ):
        raise OfflineExportError(f"BBT start invalide : {bbt!r}")

    return (
        (bar - 1) * beats_per_bar
        + (beat - 1)
        + (sixteenth - 1) / 4.0
    )


def _bbt_length_to_live_beats(
    bbt: tuple[int, int, int],
    beats_per_bar: int = 4,
) -> float:
    bars, beats, sixteenths = (int(value) for value in bbt)

    if (
        beats_per_bar <= 0
        or bars < 0
        or beats < 0
        or beats >= beats_per_bar
        or sixteenths < 0
        or sixteenths > 3
    ):
        raise OfflineExportError(f"BBT length invalide : {bbt!r}")

    return (
        bars * beats_per_bar
        + beats
        + sixteenths / 4.0
    )


def _offline_live_loop_request(payload: dict) -> dict:
    request = urllib.request.Request(
        _OFFLINE_LIVE_LOOP_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=3.0) as response:
            raw = response.read().decode("utf-8", errors="replace")

    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = ""

        try:
            message = json.loads(detail).get("message")
        except Exception:
            message = None

        raise OfflineExportError(
            message
            or f"backend Show Audio HTTP {exc.code}"
        ) from exc

    except urllib.error.URLError as exc:
        raise OfflineExportError(
            f"backend Show Audio indisponible : {exc.reason}"
        ) from exc

    except OSError as exc:
        raise OfflineExportError(
            f"backend Show Audio inaccessible : {exc}"
        ) from exc

    try:
        result = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise OfflineExportError(
            "réponse backend Show Audio invalide"
        ) from exc

    if not isinstance(result, dict) or not result.get("ok"):
        raise OfflineExportError(
            str(
                result.get("message")
                if isinstance(result, dict)
                else "transaction Live refusée"
            )
        )

    return result


def _restore_live_loop_state(state: dict[str, Any]) -> None:
    _offline_live_loop_request({
        "action": "restore",
        "loop_start": float(state["loop_start"]),
        "loop_length": float(state["loop_length"]),
        "loop": bool(state["loop"]),
    })


def _prepare_live_export_loop(
    *,
    start_bbt: tuple[int, int, int],
    length_bbt: tuple[int, int, int],
) -> dict[str, Any]:
    target_start = _bbt_start_to_live_beats(start_bbt)
    target_length = _bbt_length_to_live_beats(length_bbt)

    if target_length <= 0:
        raise OfflineExportError("longueur Live offline nulle")

    response = _offline_live_loop_request({
        "action": "prepare",
        "loop_start": target_start,
        "loop_length": target_length,
        "loop": True,
    })

    print("[OFFLINE_TIMING] LIVE_LOOP prepare " + json.dumps({
        "requested_start_bbt": start_bbt, "requested_length_bbt": length_bbt,
        "requested_start_beats": target_start, "requested_length_beats": target_length,
        "previous": response.get("previous"), "target": response.get("target"),
        "confirmed": response.get("confirmed"),
    }, sort_keys=True), flush=True)

    previous = response.get("previous")

    if not isinstance(previous, dict):
        raise OfflineExportError(
            "état Live précédent absent"
        )

    for key in ("loop_start", "loop_length", "loop"):
        if key not in previous:
            raise OfflineExportError(
                f"état Live précédent incomplet : {key}"
            )

    # Laisse le thread Remote Script appliquer les propriétés
    # avant l'ouverture du dialogue Export.
    time.sleep(0.15)

    return previous


def wav_export_parameters(settings: dict) -> dict:
    wav_formats = [
        item for item in settings.get("formats") or [] if item.get("format") == "wav"
    ]
    if len(wav_formats) != 1:
        raise OfflineExportError("la V1 offline exige exactement un format WAV")
    depth = wav_formats[0].get("bit_depth")
    if depth not in (16, 24, "float32"):
        raise OfflineExportError("resolution WAV non supportee")
    return {
        "sample_rate": int(settings.get("sample_rate")),
        "bit_depth": 32 if depth == "float32" else int(depth),
        "normalize": bool(settings.get("normalize", False)),
    }


def build_ableton_export_script(
    *, start_bbt: tuple[int, int, int], length_bbt: tuple[int, int, int],
    output_path: Path, sample_rate: int, bit_depth: int, normalize: bool,
) -> str:
    """Construit un script JXA qui cible uniquement des AXIdentifier."""
    payload = json.dumps({
        "start": list(start_bbt), "length": list(length_bbt),
        "output": str(Path(output_path).resolve()),
        "filename": Path(output_path).name,
        "sample_rate": int(sample_rate), "bit_depth": int(bit_depth),
        "normalize": bool(normalize),
    }, ensure_ascii=False, sort_keys=True)
    return f'''ObjC.import("Foundation");
const spec = {payload};
const timingStarted = Date.now();
function timing(label) {{
  console.log("[OFFLINE_TIMING] JXA +" + ((Date.now() - timingStarted) / 1000).toFixed(3) + "s " + label);
}}
timing("process:start");
const se = Application("/System/Library/CoreServices/System Events.app");
const liveMatches = se.applicationProcesses.whose({{name: "Live"}})();
if (liveMatches.length === 0) throw new Error("Ableton Live indisponible");
const live = liveMatches[0];

function isAXInvalidation(error) {{
  const message = String(error);
  return [-1719, -1728].indexOf(Number(error.number)) !== -1 ||
    /(?:-1719|-1728|Index non valide|Il est impossible d[’']obtenir l[’']objet)/i.test(message);
}}
function axid(element) {{
  try {{ return String(element.attributes.byName("AXIdentifier").value()); }}
  catch (error) {{ if (!isAXInvalidation(error)) throw error; return ""; }}
}}
function findAX(root, identifier) {{
  let children;
  let count;
  try {{ children = root.uiElements(); count = children.length; }}
  catch (error) {{ if (!isAXInvalidation(error)) throw error; return null; }}
  for (let i = 0; i < count; i++) {{
    try {{
      const child = children[i];
      if (axid(child) === identifier) return child;
      const found = findAX(child, identifier);
      if (found) return found;
    }} catch (error) {{ if (!isAXInvalidation(error)) throw error; }}
  }}
  return null;
}}
function waitAX(identifier, seconds) {{
  console.log("AX: " + identifier);
  const limit = Date.now() + seconds * 1000;
  while (Date.now() < limit) {{
    try {{
      const dialog = exportDialogWindow();
      const found = dialog ? findAX(dialog, identifier) : null;
      if (found) return found;
    }} catch (error) {{ if (!isAXInvalidation(error)) throw error; }}
    delay(0.1);
  }}
  const error = new Error("Controle AX absent: " + identifier);
  error.missingAXIdentifier = identifier;
  throw error;
}}
const bbtControlCache = {{}};

function clearBBTControlCache() {{
  const identifiers = Object.keys(bbtControlCache);
  for (let i = 0; i < identifiers.length; i++) {{
    delete bbtControlCache[identifiers[i]];
  }}
}}

function bbtControl(identifier) {{
  if (bbtControlCache[identifier]) {{
    return bbtControlCache[identifier];
  }}
  const control = waitAX(identifier, 10);
  bbtControlCache[identifier] = control;
  return control;
}}

function controlForIdentifier(identifier) {{
  if (bbtIdentifiers.indexOf(identifier) !== -1) {{
    return bbtControl(identifier);
  }}
  return waitAX(identifier, 10);
}}

function performAXAction(identifier, actionName) {{
  let control;
  try {{
    // Une action peut reutiliser un controle BBT deja valide par
    // numericAXValue(), mais ne doit pas initialiser seule le cache.
    // Le chemin transactionnel reste donc : lecture -> action -> lecture.
    if (bbtIdentifiers.indexOf(identifier) !== -1) {{
      control = bbtControlCache[identifier]
        ? bbtControlCache[identifier]
        : waitAX(identifier, 10);
    }} else {{
      control = waitAX(identifier, 10);
    }}

    const actions = control.actions();
    const count = actions.length;
    let invalidation = null;

    for (let i = 0; i < count; i++) {{
      let candidate;
      let name;
      try {{
        candidate = actions[i];
        name = String(candidate.name());
      }} catch (error) {{
        if (!isAXInvalidation(error)) throw error;
        invalidation = error;
        continue;
      }}

      if (name === actionName) {{
        // Ne jamais retenter une action dont le resultat est incertain.
        candidate.perform();
        return;
      }}
    }}

    if (invalidation) throw invalidation;
    throw new Error("Action AX absente: " + identifier + " / " + actionName);

  }} catch (error) {{
    if (
      isAXInvalidation(error) &&
      bbtIdentifiers.indexOf(identifier) !== -1
    ) {{
      delete bbtControlCache[identifier];
    }}
    throw error;
  }}
}}

function numericAXValue(identifier) {{
  let control;
  try {{
    control = controlForIdentifier(identifier);

    let raw;
    try {{
      raw = control.attributes.byName("AXValue").value();
    }} catch (error) {{
      if (isAXInvalidation(error)) throw error;
      raw = control.value();
    }}

    const value = Number(raw);

    if (
      raw === null ||
      raw === undefined ||
      String(raw).trim() === "" ||
      !Number.isFinite(value)
    ) {{
      throw new Error(
        "Valeur AX numerique illisible: " +
        identifier +
        " valeur=" +
        String(raw)
      );
    }}

    return value;

  }} catch (error) {{
    if (
      isAXInvalidation(error) &&
      bbtIdentifiers.indexOf(identifier) !== -1
    ) {{
      delete bbtControlCache[identifier];
    }}
    throw error;
  }}
}}
const bbtIdentifiers = [
  "Base.RenderStartBox.RenderStart.Bars",
  "Base.RenderStartBox.RenderStart.Beats",
  "Base.RenderStartBox.RenderStart.Subdivisions",
  "Base.RenderLengthBox.RenderLength.Bars",
  "Base.RenderLengthBox.RenderLength.Beats",
  "Base.RenderLengthBox.RenderLength.Subdivisions"
];
const completedBBT = {{}};
const maxBBTRecoveries = 3;
let bbtRecoveries = 0;
function isTransientBBTError(error) {{
  return isAXInvalidation(error) ||
    bbtIdentifiers.indexOf(error.missingAXIdentifier) !== -1;
}}
function recoverBBT(error) {{
  if (!isTransientBBTError(error)) throw error;

  // Toute récupération AX peut correspondre à une reconstruction
  // de l'arbre Accessibility : ne jamais réutiliser les anciens objets.
  clearBBTControlCache();

  while (bbtRecoveries < maxBBTRecoveries) {{
    bbtRecoveries += 1;
    try {{
      // Un arbre redevenu disponible ne demande aucune reouverture.
      if (!exportDialogControlsReady()) {{
        if (exportDialogIsOpen()) {{
          live.frontmost = true;
          se.keyCode(53);
          if (!waitExportDialogClosed(3)) continue;
        }}
        openExportDialog();
        if (!waitExportDialogReady(10)) continue;
      }}
      // Une reconstruction ne doit pas invalider les champs deja regles.
      // Echouer explicitement si Live n'a pas conserve une valeur validee.
      const identifiers = Object.keys(completedBBT);
      for (let i = 0; i < identifiers.length; i++) {{
        const identifier = identifiers[i];
        if (numericAXValue(identifier) !== completedBBT[identifier]) {{
          throw new Error("BBT deja configure modifie apres reconstruction: " + identifier);
        }}
      }}
      return;
    }} catch (nextError) {{
      if (!isTransientBBTError(nextError)) throw nextError;
      error = nextError;
    }}
  }}
  throw new Error("Limite recuperations AX BBT atteinte (3): " + String(error));
}}
function setAXNumericByActions(identifier, wanted) {{
  if (bbtIdentifiers.indexOf(identifier) === -1) {{
    throw new Error("Controle BBT inconnu: " + identifier);
  }}
  const target = Number(wanted);
  if (!Number.isFinite(target)) {{
    throw new Error("Cible BBT invalide: " + identifier + " valeur=" + String(wanted));
  }}
  const maxSteps = 256;
  let steps = 0;
  while (true) {{
    try {{
      // Nouvelle lecture apres toute erreur, avant de choisir UNE action.
      const current = numericAXValue(identifier);
      if (current === target) {{
        completedBBT[identifier] = current;
        return;
      }}
      if (steps >= maxSteps) throw new Error("Limite actions AX BBT atteinte: " + identifier);
      const actionName = current < target ? "AXIncrement" : "AXDecrement";
      steps += 1;
      performAXAction(identifier, actionName);
      const next = numericAXValue(identifier);
      if (next === current) {{
        throw new Error("Action AX BBT sans effet: " + identifier + " action=" + actionName);
      }}
    }} catch (error) {{
      recoverBBT(error);
    }}
  }}
}}

function setBBT(prefix, values) {{
  if (!values || values.length !== 3) {{
    throw new Error(
      "Triplet BBT invalide: " + prefix
    );
  }}

  const barsIdentifier =
    prefix + ".Bars";

  const beatsIdentifier =
    prefix + ".Beats";

  const subdivisionsIdentifier =
    prefix + ".Subdivisions";

  // Aucune navigation clavier.
  // Aucun Cmd+A.
  // Aucun Tab.
  // Aucun Return.
  //
  // Les trois AXSlider sont réglés uniquement avec leurs actions
  // AXIncrement / AXDecrement, validées sur Ableton Live réel.
  setAXNumericByActions(
    barsIdentifier,
    values[0]
  );

  setAXNumericByActions(
    beatsIdentifier,
    values[1]
  );

  setAXNumericByActions(
    subdivisionsIdentifier,
    values[2]
  );
}}

const exportControlCache = {{}};

const exportControlIdentifiers = [
  "Base.RenderedTrack",
  "Base.SampleRateBox.SampleRate",
  "Base.EncodePcmBox.EncodePcm",
  "Base.FileTypeBox.FileType",
  "Base.FileTypeOptionsBox.FileTypeOptionsCardView.BitDepthBox.BitDepth",
  "Base.NormalizeBox.Normalize",
  "Base.EncodeMp3Box.EncodeMp3"
];

function clearExportControlCache() {{
  const identifiers = Object.keys(exportControlCache);
  for (let i = 0; i < identifiers.length; i++) {{
    delete exportControlCache[identifiers[i]];
  }}
}}

function collectExportControls(element) {{
  try {{
    const identifier = axid(element);
    if (
      identifier &&
      exportControlIdentifiers.indexOf(identifier) !== -1
    ) {{
      exportControlCache[identifier] = element;
    }}
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    return;
  }}

  let children;
  try {{
    children = element.uiElements();
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    return;
  }}

  const count = children.length;
  for (let i = 0; i < count; i++) {{
    try {{
      collectExportControls(children[i]);
    }} catch (error) {{
      if (!isAXInvalidation(error)) throw error;
    }}
  }}
}}

function primeExportControlCache() {{
  clearExportControlCache();

  const dialog = exportDialogWindow();
  if (!dialog) return;

  collectExportControls(dialog);
}}

function exportControl(identifier) {{
  if (exportControlCache[identifier]) {{
    return exportControlCache[identifier];
  }}

  const control = waitAX(identifier, 10);

  if (exportControlIdentifiers.indexOf(identifier) !== -1) {{
    exportControlCache[identifier] = control;
  }}

  return control;
}}

function setToggle(identifier, wanted) {{
  let control;

  try {{
    control = exportControl(identifier);
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    clearExportControlCache();
    control = waitAX(identifier, 10);
  }}
  const current = String(control.value()).toLowerCase();
  const enabled = current === "1" || current === "on";
  if (enabled !== wanted) control.click();
}}
function choose(identifier, label) {{
  const wanted = String(label);
  let popup;

  try {{
    popup = exportControl(identifier);
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    clearExportControlCache();
    popup = waitAX(identifier, 10);
  }}

  let current = "";
  try {{
    current = String(popup.value());
  }} catch (_) {{}}

  // Certains AXPopUpButton de Live exposent leur valeur,
  // mais pas leur menu. Si la valeur est déjà correcte,
  // surtout ne pas ouvrir le menu.
  if (current === wanted) {{
    return;
  }}

  popup.click();
  delay(0.20);

  // Ableton peut reconstruire l'arbre AX après le clic.
  popup = waitAX(identifier, 10);

  let menu = null;
  try {{
    const menus = popup.menus();
    if (menus.length) {{
      menu = menus[0];
    }}
  }} catch (_) {{}}

  if (!menu) {{
    throw new Error(
      "Menu AX inaccessible: " +
      identifier +
      " actuel=" + current +
      " attendu=" + wanted
    );
  }}

  let item = null;

  try {{
    const items = menu.menuItems();

    const count = items.length;
    for (let i = 0; i < count; i++) {{
      let candidate;
      let name = "";
      try {{
        candidate = items[i];
        name = String(candidate.name());
      }} catch (error) {{
        if (!isAXInvalidation(error)) throw error;
        continue;
      }}

      if (name === wanted) {{
        item = candidate;
        break;
      }}
    }}
  }} catch (error) {{ if (!isAXInvalidation(error)) throw error; }}

  if (!item) {{
    throw new Error(
      "Option absente: " +
      identifier +
      " actuel=" + current +
      " attendu=" + wanted
    );
  }}

  item.click();
  delay(0.15);

  // Vérification après sélection.
  // Réutiliser le contrôle si Ableton ne l'a pas invalidé.
  let verificationControl;
  try {{
    verificationControl = exportControl(identifier);
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    clearExportControlCache();
    verificationControl = waitAX(identifier, 10);
  }}

  const actual = String(verificationControl.value());

  if (actual !== wanted) {{
    throw new Error(
      "Valeur popup non appliquee: " +
      identifier +
      " attendu=" + wanted +
      " lu=" + actual
    );
  }}
}}

function exportDialogWindow() {{
  try {{
    const wins = live.windows();

    const count = wins.length;
    for (let i = 0; i < count; i++) {{
      let window;
      let wname = "";
      try {{
        window = wins[i];
        wname = String(window.name());
      }} catch (error) {{
        if (!isAXInvalidation(error)) throw error;
        continue;
      }}

      if (
        wname === "Exporter Audio/Vidéo" ||
        wname === "Export Audio/Video"
      ) {{
        return window;
      }}
    }}
  }} catch (error) {{ if (!isAXInvalidation(error)) throw error; }}

  return null;
}}

function exportDialogIsOpen() {{
  return exportDialogWindow() !== null;
}}

function exportDialogControlsReady() {{
  const dialog = exportDialogWindow();

  if (!dialog) {{
    return false;
  }}

  try {{
    for (let i = 0; i < bbtIdentifiers.length; i++) {{
      if (!findAX(dialog, bbtIdentifiers[i])) return false;
    }}
    return true;
  }} catch (error) {{
    if (!isAXInvalidation(error)) throw error;
    return false;
  }}
}}

function waitExportDialogReady(seconds) {{
  const limit = Date.now() + seconds * 1000;

  while (Date.now() < limit) {{
    if (exportDialogControlsReady()) {{
      return true;
    }}

    delay(0.10);
  }}

  return false;
}}

function waitExportDialogClosed(seconds) {{
  const limit = Date.now() + seconds * 1000;

  while (Date.now() < limit) {{
    if (!exportDialogIsOpen()) {{
      return true;
    }}

    delay(0.10);
  }}

  return false;
}}

function openExportDialog() {{
  live.frontmost = true;
  delay(0.20);

  // Sélectionner boucle (Maj+Cmd+L), distinct de Cmd+L qui modifie la boucle.
  // Export reprend la sélection temporelle, pas les seuls marqueurs de boucle.
  timing("select_loop:start");
  se.keystroke("l", {{using:["command down", "shift down"]}});
  timing("select_loop:sent");
  // Le contrôle START BBT après ouverture reste la postcondition obligatoire.
  se.keystroke(
    "r",
    {{using:["command down", "shift down"]}}
  );
}}

// Live peut parfois afficher la fenêtre Export alors que son arbre AX
// reste partiellement construit et ne publie jamais les contrôles BBT.
// Une seule reconstruction complète du dialogue est autorisée.
//
// Aucun BBT n'est saisi avant confirmation explicite que RenderStart
// est réellement disponible.
timing("export_dialog:wait_start");
const wasExportOpen = exportDialogIsOpen();
timing("export_dialog:initial_open=" + wasExportOpen);
if (wasExportOpen) {{
  // Le dialogue ouvert avant la préparation OSC conserve son ancienne plage.
  // Reprendre la boucle confirmée en ouvrant un nouveau dialogue Export.
  timing("export_dialog:stale_close_start");
  live.frontmost = true;
  se.keyCode(53);
  if (!waitExportDialogClosed(3)) {{
    throw new Error("Dialogue Export precedent impossible a fermer");
  }}
  timing("export_dialog:stale_close_done");
}}
openExportDialog();
timing("export_dialog:fresh_open_requested");

let exportDialogReady =
  waitExportDialogReady(10);

if (!exportDialogReady) {{
  // Fermer uniquement le dialogue Export incomplet.
  // Aucun rendu ni Save Panel n'a encore été déclenché à ce stade.
  if (exportDialogIsOpen()) {{
    live.frontmost = true;
    delay(0.10);
    se.keyCode(53);
  }}

  if (!waitExportDialogClosed(3)) {{
    throw new Error(
      "Dialogue Export incomplet impossible a fermer"
    );
  }}

  // Repartir d'un arbre AX neuf.
  delay(0.20);
  openExportDialog();

  exportDialogReady =
    waitExportDialogReady(10);
}}

if (!exportDialogReady) {{
  throw new Error(
    "Dialogue Export controles BBT non prets apres retry"
  );
}}

timing("export_dialog:ready");

function assertBBT(prefix, values) {{
  const names = ["Bars", "Beats", "Subdivisions"];

  for (let i = 0; i < names.length; i++) {{
    const identifier = prefix + "." + names[i];
    timing("assert_bbt:" + names[i] + ":start");
    const actual = numericAXValue(identifier);
    const wanted = Number(values[i]);
    timing("assert_bbt:" + names[i] + ":done actual=" + actual + " wanted=" + wanted);

    if (!Number.isFinite(wanted) || actual !== wanted) {{
      throw new Error(
        "START BBT inattendu : " +
        identifier +
        " actual=" + actual +
        " wanted=" + wanted
      );
    }}
  }}
}}

function configureExportBBT() {{
  // Le START est prepare par AbletonOSC via la boucle Live.
  // Ne jamais tenter de le rejoindre par des milliers d'AXIncrement.
  timing("configure_bbt:start_assert");
  assertBBT(
    "Base.RenderStartBox.RenderStart",
    spec.start
  );
  timing("configure_bbt:done_assert");

  // Seule la duree reste corrigee par actions AX bornees.
  timing("configure_bbt:start_length");
  setBBT(
    "Base.RenderLengthBox.RenderLength",
    spec.length
  );
  timing("configure_bbt:done_length");
}}

timing("configure_bbt:start");
configureExportBBT();
timing("configure_bbt:done");

timing("export_controls_cache:start");
primeExportControlCache();
timing("export_controls_cache:done");

timing("configure:Base.RenderedTrack:start");
choose("Base.RenderedTrack", "Main");
timing("configure:Base.RenderedTrack:done");
timing("configure:Base.SampleRateBox.SampleRate:start");
choose("Base.SampleRateBox.SampleRate", String(spec.sample_rate));
timing("configure:Base.SampleRateBox.SampleRate:done");
timing("configure:Base.EncodePcmBox.EncodePcm:start");
setToggle("Base.EncodePcmBox.EncodePcm", true);
timing("configure:Base.EncodePcmBox.EncodePcm:done");
timing("configure:Base.FileTypeBox.FileType:start");
choose("Base.FileTypeBox.FileType", "WAV");
timing("configure:Base.FileTypeBox.FileType:done");
timing("configure:Base.FileTypeOptionsBox.FileTypeOptionsCardView.BitDepthBox.BitDepth:start");
choose("Base.FileTypeOptionsBox.FileTypeOptionsCardView.BitDepthBox.BitDepth", String(spec.bit_depth));
timing("configure:Base.FileTypeOptionsBox.FileTypeOptionsCardView.BitDepthBox.BitDepth:done");
timing("configure:Base.NormalizeBox.Normalize:start");
setToggle("Base.NormalizeBox.Normalize", spec.normalize);
timing("configure:Base.NormalizeBox.Normalize:done");
timing("configure:Base.EncodeMp3Box.EncodeMp3:start");
setToggle("Base.EncodeMp3Box.EncodeMp3", false);
timing("configure:Base.EncodeMp3Box.EncodeMp3:done");
timing("export_configured:return");
// Le helper natif possède Export et tout le Save Panel.
JSON.stringify({{state: "export_configured", pid: live.unixId()}});'''


_NATIVE_SAVE_AX_SWIFT = r"""
import Foundation
import AppKit
import ApplicationServices

let timingStarted = ProcessInfo.processInfo.systemUptime
func timing(_ label: String) {
    let elapsed = ProcessInfo.processInfo.systemUptime - timingStarted
    let line = String(format: "[OFFLINE_TIMING] NATIVE +%.3fs %@\n", elapsed, label)
    FileHandle.standardError.write(Data(line.utf8))
}
timing("process:start")
var lastAXError: Int32 = 0
func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    if result != .success { lastAXError = result.rawValue; return nil }
    return value
}
func str(_ element: AXUIElement, _ name: String) -> String {
    return attr(element, name).map { String(describing: $0) } ?? ""
}
func find(_ element: AXUIElement, _ id: String, _ depth: Int = 0) -> AXUIElement? {
    if depth > 30 { return nil }
    if str(element, kAXIdentifierAttribute) == id { return element }
    for child in attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let result = find(child, id, depth + 1) { return result }
    }
    return nil
}
func fail(_ stage: String) -> Never {
    timing("failure:\(stage)")
    print("ERROR=\(stage) AX_ERROR=\(lastAXError)")
    exit(1)
}
guard AXIsProcessTrusted() else { fail("ACCESSIBILITY_NOT_TRUSTED") }
guard CommandLine.arguments.count == 3,
      let pid = Int32(CommandLine.arguments[2]), pid > 0,
      let live = NSRunningApplication(processIdentifier: pid),
      live.bundleIdentifier == "com.ableton.live", !live.isTerminated else {
    fail("LIVE_PID_INVALID")
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 2)
print("PID=\(pid)")
func windows() -> [AXUIElement]? {
    return attr(app, kAXWindowsAttribute) as? [AXUIElement]
}
func panel(_ windows: [AXUIElement]) -> AXUIElement? {
    for window in windows {
        if let result = find(window, "save-panel") { return result }
    }
    return nil
}
timing("export_lookup:start")
guard let initial = windows() else { fail("WINDOWS_UNREADABLE") }
for window in initial {
    print("WINDOW=\(str(window, kAXTitleAttribute)) ID=\(str(window, kAXIdentifierAttribute))")
}
guard panel(initial) == nil else { fail("PREEXISTING_SAVE_PANEL") }
guard let export = initial.compactMap({ find($0, "Base.FinalButtonsBox.ExportButton") }).first else {
    fail("EXPORT_BUTTON_ABSENT")
}
timing("export_press:start")
let exportResult = AXUIElementPerformAction(export, kAXPressAction as CFString)
timing("export_press:done")
print("EXPORT_AXPRESS_RESULT=\(exportResult.rawValue)")
// Ableton peut ouvrir le Save Panel tout en retournant
// kAXErrorCannotComplete (-25204). Ne jamais retenter le clic.
// La boucle suivante vérifie l'effet réel par apparition du Save Panel.
guard exportResult == .success || exportResult.rawValue == -25204 else {
    fail("EXPORT_PRESS_FAILED")
}
let expected = CommandLine.arguments[1]
let noExtension = (expected as NSString).deletingPathExtension
let deadline = Date().addingTimeInterval(30)
var stage = "WAIT_SAVE_PANEL"
timing("save_panel:wait_start")
var panelSeen = false
var written = false
var pressed = false
while Date() < deadline {
    guard !live.isTerminated else { fail("LIVE_PROCESS_TERMINATED") }
    stage = "READ_WINDOWS"
    guard let current = windows() else { usleep(100_000); continue }
    stage = pressed ? "WAIT_SAVE_PANEL_CLOSE" : "WAIT_SAVE_PANEL"
    guard let currentPanel = panel(current) else {
        if pressed { timing("save_panel:closed"); timing("process:return"); print("NATIVE_SAVE_OK"); exit(0) }
        usleep(100_000); continue
    }
    if !panelSeen { timing("save_panel:found"); panelSeen = true }
    if pressed { stage = "WAIT_SAVE_PANEL_CLOSE"; usleep(100_000); continue }
    stage = "WAIT_SAVE_NAME_FIELD"
    guard let field = find(currentPanel, "saveAsNameTextField") else { usleep(100_000); continue }
    if !written {
        timing("save_name:write_start")
        let result = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, expected as CFString)
        print("SAVE_NAME_WRITE_RESULT=\(result.rawValue)")
        guard result == .success else { fail("SAVE_NAME_WRITE_FAILED") }
        timing("save_name:write_done")
        written = true
        usleep(100_000)
        continue // Reacquisition après écriture.
    }
    let actual = str(field, kAXValueAttribute)
    stage = "WAIT_EXPECTED_NAME actual=\(actual) expected=\(expected)"
    guard actual == expected || actual == noExtension else { usleep(100_000); continue }
    stage = "WAIT_OKBUTTON"
    guard let button = find(currentPanel, "OKButton") else { usleep(100_000); continue }
    guard str(button, kAXRoleAttribute) == "AXButton" else { fail("OKBUTTON_BAD_ROLE") }
    stage = "WAIT_OKBUTTON_ENABLED"
    guard (attr(button, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else {
        usleep(100_000); continue
    }
    print("SAVE_NAME=\(actual) BUTTON=OKButton TITLE=\(str(button, kAXTitleAttribute)) ENABLED=1")
    timing("save_press:start")
    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
    timing("save_press:done")
    print("AXPRESS_RESULT=\(result.rawValue)")
    // Même règle pour Enregistrer : -25204 est un résultat incertain.
// Ne jamais recliquer ; vérifier ensuite la disparition du Save Panel.
guard result == .success || result.rawValue == -25204 else {
    fail("SAVE_PRESS_FAILED")
}
    pressed = true
    timing("save_panel:close_wait_start")
}
fail(stage)
"""


def run_macos_automation(script: str, *, timeout: float = 300.0) -> str:
    """JXA configure, puis un unique processus natif possède Export et Save.

    Cache de modules Swift conservé ; source et exécutable restent temporaires.
    Compilation avant toute interaction GUI. Chaque sous-processus est attendu
    et récolté, y compris sur timeout ; aucun thread ni watcher concurrent.
    """
    match = re.search(r"const spec = (\{.*?\});", script)
    if match is None:
        raise OfflineExportError("spec export absente")
    filename = json.loads(match.group(1))["filename"]
    started = time.monotonic()
    deadline = started + float(timeout)

    def timing(label):
        print(f"[OFFLINE_TIMING] AUTOMATION +{time.monotonic() - started:.3f}s {label}", flush=True)

    def run_timed(command, **kwargs):
        timing(f"{stage}:start")
        try:
            result = subprocess.run(command, **kwargs)
        except (OSError, subprocess.SubprocessError) as exc:
            relay(exc)
            timing(f"{stage}:failed")
            raise
        relay(result)
        timing(f"{stage}:done")
        return result

    def relay(result):
        # Borné : seules les marques internes sont relayées, même sur timeout.
        for value in (getattr(result, "stdout", None), getattr(result, "stderr", None)):
            if isinstance(value, bytes):
                value = value.decode(errors="replace")
            for line in (value or "").splitlines()[:200]:
                if line.startswith("[OFFLINE_TIMING]"):
                    print(line[:500], flush=True)

    def remaining(cap):
        budget = deadline - time.monotonic()
        if budget <= 0:
            raise OfflineExportError(f"{stage}: délai global dépassé ({timeout:g} s)")
        return min(cap, budget)

    stage = "compile_native"
    try:
        with tempfile.TemporaryDirectory(prefix="cl_show_audio_ax_") as directory:
            source = Path(directory) / "save.swift"
            binary = Path(directory) / "save"
            source.write_text(_NATIVE_SAVE_AX_SWIFT, encoding="utf-8")
            timing("swift_module_cache:load_start")
            # Le dossier temporaire macOS est propre à l'utilisateur. Conserver
            # les modules évite leur reconstruction (~25 s mesurées), sans
            # réutiliser un exécutable potentiellement périmé.
            modules = Path(tempfile.gettempdir()) / f"cl_show_audio_swift_modules_{os.getuid()}"
            modules.mkdir(mode=0o700, parents=True, exist_ok=True)
            timing("swift_module_cache:load_done")
            run_timed(
                ["/usr/bin/swiftc", "-module-cache-path", str(modules),
                 str(source), "-o", str(binary)],
                check=True, capture_output=True, text=True, timeout=remaining(60),
            )
            stage = "configure_export_jxa"
            configured = run_timed(
                ["/usr/bin/osascript", "-l", "JavaScript", "-e", script],
                check=True, capture_output=True, text=True, timeout=remaining(90),
            )
            try:
                ready = json.loads(configured.stdout)
                pid = ready["pid"]
                if ready["state"] != "export_configured" or type(pid) is not int or pid <= 0:
                    raise ValueError("state/pid invalide")
            except (ValueError, KeyError, TypeError) as exc:
                raise OfflineExportError("JXA: export_configured/PID non confirme") from exc
            stage = "native_export_save"
            saved = run_timed(
                [str(binary), filename, str(pid)], check=True, capture_output=True,
                text=True, timeout=remaining(40),
            )
            if "NATIVE_SAVE_OK" not in saved.stdout.splitlines():
                raise OfflineExportError("fermeture Save Panel non confirmee")
            timing("processes:complete")
            return saved.stdout.strip()
    except (OSError, subprocess.SubprocessError) as exc:
        if isinstance(exc, subprocess.TimeoutExpired):
            details = [f"délai dépassé ({exc.timeout:g} s)"]
        elif isinstance(exc, subprocess.CalledProcessError):
            details = [f"processus terminé avec code {exc.returncode}"]
        else:
            details = [str(exc)]
        for value in (getattr(exc, "stdout", None), getattr(exc, "stderr", None)):
            if value:
                details.append((value.decode(errors="replace") if isinstance(value, bytes) else value)[-2000:])
        raise OfflineExportError(f"{stage}: " + "\n".join(details)) from exc


def validate_wav_file(
    path: Path, *, expected_duration: float, expected_sample_rate: int,
    tolerance_seconds: float = 0.20,
) -> dict:
    target = Path(path)
    if not target.is_file() or target.stat().st_size <= 80:
        raise OfflineExportError("fichier WAV absent ou vide")
    try:
        with wave.open(str(target), "rb") as handle:
            channels = handle.getnchannels()
            sample_rate = handle.getframerate()
            sample_width = handle.getsampwidth()
            frame_count = handle.getnframes()
    except (OSError, wave.Error) as exc:
        raise OfflineExportError("fichier WAV illisible") from exc
    duration = frame_count / sample_rate if sample_rate else 0.0
    if abs(duration - float(expected_duration)) > tolerance_seconds:
        raise OfflineExportError(
            f"duree WAV incoherente: {duration:.3f}s / {expected_duration:.3f}s"
        )
    if sample_rate != int(expected_sample_rate):
        raise OfflineExportError("frequence WAV incoherente")
    return {
        "path": str(target), "size": target.stat().st_size,
        "duration_seconds": duration, "sample_rate": sample_rate,
        "channels": channels, "bit_depth": sample_width * 8,
    }


def execute_offline_wav(
    *, zone: dict, settings: dict, output_path: Path, tempo: float,
    automation: Callable[[str], Any] | None = None, timeout: float = 300.0,
) -> dict:
    """Execute un rendu Ableton offline puis publie atomiquement le WAV valide."""
    render_candidate: Path | None = None
    partial_path: Path | None = None

    try:
        parameters = wav_export_parameters(settings)
        start = beats_to_bbt(zone["start_beats"])
        length = beats_to_length_bbt(zone["duration_beats"])

        expected_seconds = zone.get("expected_duration_seconds")
        if expected_seconds is None:
            expected_seconds = (
                float(zone["duration_beats"]) * 60.0 / float(tempo)
            )

        target = Path(output_path).expanduser().resolve()
        target.parent.mkdir(parents=True, exist_ok=True)

        # Ableton peut mémoriser le dernier dossier du Save Panel.
        # On lui donne donc un nom unique, puis on retrouve ce fichier
        # après le rendu dans les destinations explicites surveillées ci-dessous.
        render_token = uuid.uuid4().hex[:12]
        render_name = (
            f"{target.stem}.__clrender_{render_token}{target.suffix or '.wav'}"
        )
        requested_render_path = target.with_name(render_name)

        command = build_ableton_export_script(
            start_bbt=start,
            length_bbt=length,
            output_path=requested_render_path,
            sample_rate=parameters["sample_rate"],
            bit_depth=parameters["bit_depth"],
            normalize=parameters["normalize"],
        )

        started = time.monotonic()

        def timing(label: str) -> None:
            print(
                f"[OFFLINE_TIMING] +{time.monotonic() - started:.3f}s {label}",
                flush=True,
            )

        timing("execute_offline_wav:start")
        print("[OFFLINE_TIMING] EXPORT_ZONE " + json.dumps({
            "type": zone.get("type"), "start_beats": zone["start_beats"],
            "duration_beats": zone["duration_beats"], "start_bbt": start,
            "length_bbt": length,
        }, sort_keys=True), flush=True)

        # Compatibilité des automations injectées : un WAV valide peut être
        # récupéré après une SubprocessError. En production, le pilote rapporte
        # directement toute erreur avec son étape ; aucun recovery Save tardif.
        # Garder la transaction exclusive jusqu'au WAV validé : la fermeture
        # du Save Panel ne signifie pas que le rendu Ableton est terminé.
        with (_LIVE_EXPORT_LOCK if automation is None else nullcontext()):
            previous_loop_state = None
            try:
                automation_error = None
                try:
                    if automation is None:
                        timing("prepare_live_loop:start")
                        previous_loop_state = _prepare_live_export_loop(
                            start_bbt=start, length_bbt=length,
                        )
                        timing("prepare_live_loop:done")
                        timing("macos_automation:start")
                        run_macos_automation(command, timeout=float(timeout))
                        timing("macos_automation:done")
                    else:
                        automation(command)
                except subprocess.SubprocessError as exc:
                    # Compatibilité des automations injectées après lancement du rendu.
                    automation_error = exc

                deadline = started + float(timeout)

                # Si une automation injectée a échoué, on conserve une courte
                # fenêtre de récupération : Ableton peut malgré tout avoir déjà
                # lancé le rendu.
                #
                # En revanche, si aucun fichier n'apparaît rapidement, inutile
                # d'attendre le timeout complet de 300 s.
                automation_error_deadline = None

                if automation_error is not None:
                    automation_error_deadline = min(
                        deadline,
                        time.monotonic() + 15.0,
                    )

                stable_size: int | None = None
                stable_count = 0

                # Liste fixe, sans parcours du disque : dossier technique,
                # dossier final, Bureau (destination macOS mémorisée), racine tmp.
                # Le nom contient le jeton propre à cette transaction ; ne jamais
                # récupérer un ancien WAV portant seulement le nom final.
                candidates = tuple(dict.fromkeys(
                    (directory / render_name).resolve()
                    for directory in (
                        target.parent, target.parent.parent,
                        Path.home() / "Desktop", Path("/private/tmp"),
                    )
                ))
                print(
                    "[OFFLINE_RENDER_LOOKUP]",
                    f"target={target}",
                    f"candidates={list(map(str, candidates))}",
                    flush=True,
                )

                def find_render_candidate() -> Path | None:
                    matches = [path for path in candidates if path.is_file()]
                    if len(matches) > 1:
                        raise OfflineExportError(
                            "WAV Ableton ambigu : plusieurs fichiers pour le rendu "
                            + render_name
                        )
                    return matches[0] if matches else None

                while time.monotonic() < deadline:
                    if (
                        automation_error_deadline is not None
                        and time.monotonic() >= automation_error_deadline
                        and render_candidate is None
                    ):
                        raise automation_error

                    candidate = find_render_candidate()

                    if candidate is not None and render_candidate is None:
                        timing(f"render_candidate:found:{candidate}")

                    if candidate is None:
                        stable_size = None
                        stable_count = 0
                        time.sleep(0.20)
                        continue

                    try:
                        size = candidate.stat().st_size
                    except OSError:
                        stable_size = None
                        stable_count = 0
                        time.sleep(0.20)
                        continue

                    if size <= 80:
                        stable_size = size
                        stable_count = 0
                        time.sleep(0.20)
                        continue

                    if candidate == render_candidate and size == stable_size:
                        stable_count += 1
                    else:
                        stable_size = size
                        stable_count = 0

                    render_candidate = candidate

                    # 6 contrôles espacés de 250 ms = environ 1,5 s sans croissance.
                    if stable_count >= 6:
                        timing("render_candidate:stable")
                        break

                    time.sleep(0.25)
                else:
                    if automation_error is not None:
                        raise automation_error
                    raise OfflineExportError("delai de rendu Ableton depasse")

                if render_candidate is None:
                    raise OfflineExportError("WAV Ableton introuvable")

                # Validation AVANT publication du fichier final.
                timing("wav_validation:start")
                validation = validate_wav_file(
                    render_candidate,
                    expected_duration=expected_seconds,
                    expected_sample_rate=parameters["sample_rate"],
                )
                timing("wav_validation:done")
            finally:
                if previous_loop_state is not None:
                    timing("restore_live_loop:start")
                    _restore_live_loop_state(previous_loop_state)
                    timing("restore_live_loop:done")


        partial_path = target.with_name(
            f".{target.name}.{render_token}.partial"
        )

        if partial_path.exists():
            partial_path.unlink()

        # Copie vers le filesystem final puis rename atomique.
        timing("master_copy:start")
        shutil.copy2(render_candidate, partial_path)
        timing("master_copy:done")

        # On valide également la copie avant publication.
        final_validation = validate_wav_file(
            partial_path,
            expected_duration=expected_seconds,
            expected_sample_rate=parameters["sample_rate"],
        )

        os.replace(partial_path, target)
        partial_path = None
        timing("master_publish:done")

        # Le master temporaire Ableton n'est plus nécessaire.
        if render_candidate != target:
            try:
                render_candidate.unlink()
            except OSError:
                pass

        result_file = dict(final_validation)
        result_file["path"] = str(target)

        return {
            "status": OFFLINE_SUCCESS,
            "mode": "OFFLINE_ABLETON",
            "render_seconds": time.monotonic() - started,
            "zone": dict(zone),
            "file": result_file,
            "render_source": str(render_candidate),
        }

    except OfflineExportError as exc:
        if partial_path is not None:
            try:
                partial_path.unlink()
            except OSError:
                pass

        return {
            "status": OFFLINE_FAILED,
            "error": str(exc),
            "fallback": "realtime",
        }

    except (OSError, subprocess.SubprocessError) as exc:
        if partial_path is not None:
            try:
                partial_path.unlink()
            except OSError:
                pass

        return {
            "status": OFFLINE_UNAVAILABLE,
            "error": str(exc),
            "fallback": "realtime",
        }
