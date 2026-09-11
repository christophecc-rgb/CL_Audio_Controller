"""Scanner read-only du Live Set pour CL Show Audio Builder.

Ce programme :
- réutilise OSCTransport ;
- ne passe pas par app.py ;
- n'envoie que des requêtes /get/ ;
- ne lance aucune scène ;
- ne modifie aucun paramètre Ableton ;
- ne touche ni au MIDI, ni au LTC, ni aux Program Changes.
"""

from __future__ import annotations

import argparse
import socket
import threading
import time
from pathlib import Path
from typing import Any

from osc_transport import (
    LOCAL_ABLETON_HOST,
    LOCAL_ABLETON_REPLY_PORT,
    LOCAL_ABLETON_SEND_PORT,
    OSCTransport,
)
from show_audio_ableton import ShowAudioAbletonAdapter
from show_audio_builder import load_show_audio_document
from show_audio_plan import (
    STATUS_DISABLED,
    STATUS_MISMATCH,
    STATUS_MISSING,
    STATUS_READY,
    build_export_plan,
    export_item_label,
)


DEFAULT_TIMEOUT = 0.30


def is_read_only_address(address: str) -> bool:
    address = str(address or "").strip()

    if not address.startswith("/live/"):
        return False

    return "/get/" in address


class ReadOnlyOSCQuery:
    """Barrière de sécurité devant OSCTransport."""

    def __init__(
        self,
        transport: OSCTransport,
        *,
        timeout: float = DEFAULT_TIMEOUT,
    ):
        self.transport = transport
        self.timeout = float(timeout)

    def __call__(
        self,
        address: str,
        *args: Any,
        apply_response: bool = False,
        timeout: float | None = None,
        **_ignored: Any,
    ):
        if not is_read_only_address(address):
            raise RuntimeError(
                f"commande OSC refusée par le scanner read-only : {address}"
            )

        return self.transport.query(
            address,
            *args,
            timeout=self.timeout if timeout is None else float(timeout),
        )


def udp_port_available(host: str, port: int) -> bool:
    """Vérifie qu'un listener UDP peut être ouvert localement."""

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        sock.bind((host, int(port)))
    except OSError:
        return False
    finally:
        sock.close()

    return True


def start_reply_server(
    transport: OSCTransport,
    *,
    bind_host: str = "0.0.0.0",
) -> threading.Thread:
    thread = threading.Thread(
        target=transport.serve_forever,
        kwargs={"bind_host": bind_host},
        daemon=True,
        name="CLShowAudioOSCReply",
    )
    thread.start()

    # Le serveur est local et léger. On lui laisse simplement le temps
    # d'ouvrir son socket avant la première requête.
    time.sleep(0.08)

    return thread


def load_runtime_target():
    """Réutilise la cible Ableton configurée quand elle est disponible."""

    try:
        from ableton_targets import load_target

        target = load_target()

        return {
            "host": target.host,
            "send_port": int(target.send_port),
            "reply_port": int(target.reply_port),
            "source": "ableton_targets",
        }

    except Exception:
        return {
            "host": LOCAL_ABLETON_HOST,
            "send_port": LOCAL_ABLETON_SEND_PORT,
            "reply_port": LOCAL_ABLETON_REPLY_PORT,
            "source": "defaults",
        }


def format_duration(seconds: float | None) -> str:
    if seconds is None:
        return "--:--"

    total = max(0, int(round(seconds)))
    minutes, secs = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)

    if hours:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"

    return f"{minutes:02d}:{secs:02d}"


def print_live_inventory(
    adapter: ShowAudioAbletonAdapter,
) -> None:
    scenes = adapter.list_scenes()
    tracks = adapter.list_tracks()
    tempo = adapter.get_tempo()

    print()
    print("LIVE SET")
    print(f"Scènes : {len(scenes)}")
    print(f"Pistes : {len(tracks)}")
    print(
        "Tempo  : "
        + (
            f"{tempo:g} BPM"
            if tempo is not None
            else "indisponible"
        )
    )

    print()
    print("PISTES")

    for track in tracks:
        print(
            f"  {track['track_index']:03d}  "
            f"{track['track_name']}"
        )


def print_export_plan(plan: dict) -> None:
    print()
    print("PLAN D'EXPORT")

    symbols = {
        STATUS_READY: "✓",
        STATUS_MISMATCH: "!",
        STATUS_MISSING: "×",
        STATUS_DISABLED: "-",
    }

    for item in plan["items"]:
        status = item["status"]
        symbol = symbols.get(status, "?")

        print()
        print(
            f"{symbol} {status.upper():8s} "
            f"{export_item_label(item)}"
        )

        if item["expected_scene_index"] is not None:
            print(
                "    attendu : "
                f"index {item['expected_scene_index']} "
                f"— {item['expected_scene_name'] or '-'}"
            )
        else:
            print(
                "    attendu : "
                f"{item['expected_scene_name'] or '-'}"
            )

        if item["actual_scene_index"] is not None:
            print(
                "    trouvé  : "
                f"index {item['actual_scene_index']} "
                f"— {item['actual_scene_name']}"
            )
        else:
            print("    trouvé  : —")

        print(
            f"    playback: "
            f"{item['playback'] or '-'}"
        )

        print(
            f"    sortie  : "
            f"{item['filename']}"
        )

    counts = plan["counts"]

    print()
    print("RÉSUMÉ")
    print(f"  READY     {counts[STATUS_READY]}")
    print(f"  MISMATCH  {counts[STATUS_MISMATCH]}")
    print(f"  MISSING   {counts[STATUS_MISSING]}")
    print(f"  DISABLED  {counts[STATUS_DISABLED]}")
    print(
        "  PLAN      "
        + ("PRÊT" if plan["ready"] else "À CORRIGER")
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Scanne le Live Set ouvert et construit "
            "le plan CL Show Audio en lecture seule."
        )
    )

    parser.add_argument(
        "document",
        nargs="?",
        default="show_audio.json",
    )

    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
    )

    args = parser.parse_args()

    target = load_runtime_target()

    print("CL SHOW AUDIO — LIVE SCAN")
    print(
        f"Cible OSC : "
        f"{target['host']}:{target['send_port']}"
    )
    print(
        f"Réponses  : UDP {target['reply_port']}"
    )
    print(
        f"Profil    : {target['source']}"
    )

    if not udp_port_available(
        "0.0.0.0",
        target["reply_port"],
    ):
        print()
        print(
            "ERREUR : le port UDP "
            f"{target['reply_port']} est déjà occupé."
        )
        print(
            "Le scanner refuse de créer un second "
            "récepteur OSC concurrent."
        )
        print(
            "Fermer l'instance CL Audio Controller "
            "qui utilise ce port avant ce test."
        )
        return 2

    transport = OSCTransport(
        host=target["host"],
        send_port=target["send_port"],
        reply_port=target["reply_port"],
    )

    start_reply_server(transport)

    query = ReadOnlyOSCQuery(
        transport,
        timeout=args.timeout,
    )

    adapter = ShowAudioAbletonAdapter(query)

    # Premier échange : s'il échoue, inutile de continuer.
    scenes = adapter.get_scene_names()

    if not scenes:
        diagnostics = transport.diagnostics()

        print()
        print("ERREUR : aucune scène reçue d'AbletonOSC.")
        print(
            f"connected={diagnostics.get('connected')}"
        )
        print(
            f"last_error={diagnostics.get('last_error')}"
        )
        print(
            f"timeouts={diagnostics.get('timeout_count')}"
        )
        return 3

    print_live_inventory(adapter)

    document_path = Path(args.document)
    document = load_show_audio_document(
        document_path
    )

    print()
    print(f"DOCUMENT : {document_path}")
    print(
        f"Variantes : "
        f"{len(document['variants'])}"
    )

    plan = build_export_plan(
        document,
        adapter,
    )

    print_export_plan(plan)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
