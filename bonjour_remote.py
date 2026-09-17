#!/usr/bin/env python3

import json
import re
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "config" / "ableton_remote_discovery.json"


DEFAULT_CONFIG = {
    "enabled": True,
    "service_name": "CL Ableton Distant",
    "service_type": "_apple-midi._udp",
    "osc_send_port": 11000,
    "osc_reply_port": 11001,
    "last_known_host": "",
    "last_known_ip": "",
}


def load_config():
    cfg = dict(DEFAULT_CONFIG)

    try:
        if CONFIG_PATH.exists():
            data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cfg.update(data)
    except Exception as exc:
        cfg["_config_error"] = str(exc)

    return cfg


def save_config(cfg):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

    clean = {
        key: cfg.get(key, DEFAULT_CONFIG.get(key))
        for key in DEFAULT_CONFIG
    }

    CONFIG_PATH.write_text(
        json.dumps(clean, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def resolve_ipv4(host):
    host = (host or "").rstrip(".")

    if not host:
        return None

    try:
        infos = socket.getaddrinfo(
            host,
            None,
            socket.AF_INET,
            socket.SOCK_DGRAM,
        )

        for info in infos:
            ip = info[4][0]
            if ip and not ip.startswith("127."):
                return ip
    except Exception:
        pass

    return None


def discover_service(service_name, service_type, timeout=4):
    cmd = [
        "dns-sd",
        "-L",
        service_name,
        service_type,
        "local.",
    ]

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            output, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.terminate()

            try:
                output, _ = proc.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                output, _ = proc.communicate()

    except Exception as exc:
        return {
            "found": False,
            "error": str(exc),
        }

    match = re.search(
        r"can be reached at\s+([^:]+):(\d+)",
        output or "",
    )

    if not match:
        return {
            "found": False,
            "raw": output,
        }

    host = match.group(1).rstrip(".")
    rtp_port = int(match.group(2))
    ip = resolve_ipv4(host)

    return {
        "found": True,
        "host": host,
        "ip": ip,
        "rtp_port": rtp_port,
        "raw": output,
    }


def discover_ableton_remote():
    cfg = load_config()

    if not cfg.get("enabled", True):
        return {
            "status": "disabled",
            "config": cfg,
        }

    service_name = cfg.get("service_name") or "CL Ableton Distant"
    service_type = cfg.get("service_type") or "_apple-midi._udp"

    result = discover_service(service_name, service_type)

    if result.get("found") and result.get("ip"):
        cfg["last_known_host"] = result["host"]
        cfg["last_known_ip"] = result["ip"]
        save_config(cfg)

        return {
            "status": "bonjour",
            "service_name": service_name,
            "service_type": service_type,
            "host": result["host"],
            "ip": result["ip"],
            "rtp_port": result["rtp_port"],
            "osc_send_port": int(cfg.get("osc_send_port", 11000)),
            "osc_reply_port": int(cfg.get("osc_reply_port", 11001)),
        }

    # Fallback : dernière machine connue.
    fallback_host = cfg.get("last_known_host") or ""
    fallback_ip = resolve_ipv4(fallback_host)

    if fallback_ip:
        return {
            "status": "fallback_hostname",
            "service_name": service_name,
            "host": fallback_host,
            "ip": fallback_ip,
            "osc_send_port": int(cfg.get("osc_send_port", 11000)),
            "osc_reply_port": int(cfg.get("osc_reply_port", 11001)),
        }

    fallback_ip = cfg.get("last_known_ip") or ""

    if fallback_ip:
        return {
            "status": "fallback_ip",
            "service_name": service_name,
            "host": fallback_host or None,
            "ip": fallback_ip,
            "osc_send_port": int(cfg.get("osc_send_port", 11000)),
            "osc_reply_port": int(cfg.get("osc_reply_port", 11001)),
        }

    return {
        "status": "not_found",
        "service_name": service_name,
        "service_type": service_type,
        "host": None,
        "ip": None,
        "osc_send_port": int(cfg.get("osc_send_port", 11000)),
        "osc_reply_port": int(cfg.get("osc_reply_port", 11001)),
    }


if __name__ == "__main__":
    result = discover_ableton_remote()

    print()
    print("==========================================")
    print(" CL ABLETON REMOTE DISCOVERY")
    print("==========================================")
    print(f"Status       : {result.get('status')}")
    print(f"Service      : {result.get('service_name')}")
    print(f"Hostname     : {result.get('host') or '—'}")
    print(f"IP           : {result.get('ip') or '—'}")

    if result.get("ip"):
        print(
            f"OSC          : "
            f"{result['ip']}:{result.get('osc_send_port', 11000)}"
        )
        print(
            f"Retour       : "
            f"{result['ip']}:{result.get('osc_reply_port', 11001)}"
        )

    print("==========================================")

    sys.exit(0 if result.get("ip") else 1)
