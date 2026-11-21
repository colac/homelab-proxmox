#!/usr/bin/env python3
"""ntfy-doorbell: ring the public doorbell for messages on the private ntfy.

The phone usually runs another VPN, so it cannot reach the private server
(tailnet only). This service follows the private topics and, for a message
that needs the human, publishes a fixed text to a topic on ntfy.sh: "open
Tailscale". The doorbell never carries anything from the message but its
priority. Rules (monitoring's docs/ai-ops/architecture.md, D1):

- ring for priority >= DOORBELL_MIN_PRIORITY;
- at most once per DOORBELL_THROTTLE_MINUTES, unless the new priority is
  higher than the last ring's;
- not while the phone is online on the tailnet (it already has the message),
  except at priority 5: "online" can be stale for a while after the phone
  switched VPN, and a critical alert must not be missed.

Configuration comes from the environment (the systemd unit) and two
credentials (systemd LoadCredential): `token`, to read the private topics,
and `topic`, the doorbell topic on the public server. Standard library only.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Messages older than this when they arrive (a restart after a long outage
# replays the cache) are not worth waking anyone for.
STALE_SECONDS = 3600


def log(message: str) -> None:
    print(message, flush=True)


class Config:
    def __init__(self) -> None:
        env = os.environ
        self.private = env.get("DOORBELL_PRIVATE_URL", "http://127.0.0.1:2586").rstrip("/")
        self.topics = env["DOORBELL_TOPICS"]
        self.server = env.get("DOORBELL_SERVER", "https://ntfy.sh").rstrip("/")
        self.text = env.get("DOORBELL_TEXT", "Homelab needs you. Open Tailscale.")
        self.phone = env.get("DOORBELL_PHONE", "").strip().lower()
        self.min_priority = int(env.get("DOORBELL_MIN_PRIORITY", "3"))
        self.throttle = 60 * int(env.get("DOORBELL_THROTTLE_MINUTES", "15"))
        credentials = Path(env.get("CREDENTIALS_DIRECTORY", "/nonexistent"))
        self.token = (credentials / "token").read_text().strip()
        self.topic = (credentials / "topic").read_text().strip()
        self.state_file = Path(env.get("STATE_DIRECTORY", "/var/lib/ntfy-doorbell")) / "state.json"


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save_state(path: Path, state: dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state))
    tmp.replace(path)


def phone_online(name: str) -> bool:
    """True if the phone's node is online on the tailnet. Unknown = offline,
    so a failure here rings rather than stays quiet."""
    if not name:
        return False
    try:
        out = subprocess.run(["tailscale", "status", "--json"], capture_output=True,
                             text=True, timeout=10, check=True).stdout
        peers = (json.loads(out).get("Peer") or {}).values()
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        log(f"cannot read tailscale status ({exc}); treating the phone as offline")
        return False
    for peer in peers:
        names = {(peer.get("HostName") or "").lower(),
                 (peer.get("DNSName") or "").split(".")[0].lower()}
        if name in names:
            return bool(peer.get("Online"))
    log(f"no tailnet node named {name!r}; treating the phone as offline")
    return False


def decide(state: dict, priority: int, now: float, cfg: Config, online: bool) -> tuple[bool, str]:
    if priority < cfg.min_priority:
        return False, "below the minimum priority"
    last_ring = state.get("last_ring", 0)
    if now - last_ring < cfg.throttle and priority <= state.get("last_priority", 0):
        return False, f"rang {int(now - last_ring)} s ago at the same or a higher priority"
    if priority < 5 and online:
        return False, "the phone is online on the tailnet"
    return True, "ring"


def ring(cfg: Config, priority: int) -> None:
    req = urllib.request.Request(
        f"{cfg.server}/{cfg.topic}", data=cfg.text.encode(), method="POST",
        headers={"Priority": str(priority), "Title": "Homelab"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        resp.read()


def follow(cfg: Config, since: str):
    """Yield the private server's events. ntfy sends a keepalive every 45 s,
    so a read timeout of 120 s means the connection is dead."""
    req = urllib.request.Request(
        f"{cfg.private}/{cfg.topics}/json?since={since}",
        headers={"Authorization": f"Bearer {cfg.token}"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        for line in resp:
            if line.strip():
                yield json.loads(line)


def handle(cfg: Config, state: dict, event: dict) -> None:
    priority = int(event.get("priority") or 3)
    now = time.time()
    label = f"{event.get('topic')} {event.get('id')} (priority {priority})"
    if now - float(event.get("time", now)) > STALE_SECONDS:
        log(f"no ring for {label}: older than {STALE_SECONDS // 60} min")
        return
    online = priority < 5 and priority >= cfg.min_priority and phone_online(cfg.phone)
    ok, why = decide(state, priority, now, cfg, online)
    if not ok:
        log(f"no ring for {label}: {why}")
        return
    try:
        ring(cfg, priority)
    except (urllib.error.URLError, OSError) as exc:
        log(f"doorbell FAILED for {label}: {exc}")
        return
    state["last_ring"] = now
    state["last_priority"] = priority
    log(f"rang the doorbell for {label}")


def main() -> int:
    cfg = Config()
    state = load_state(cfg.state_file)
    # First start: only what arrives from now on.
    since = state.get("cursor") or str(int(time.time()))
    backoff = 5
    log(f"following {cfg.topics} on {cfg.private}; doorbell on {cfg.server}")
    while True:
        try:
            for event in follow(cfg, since):
                backoff = 5
                if event.get("event") != "message":
                    continue
                handle(cfg, state, event)
                since = state["cursor"] = event["id"]
                save_state(cfg.state_file, state)
            log("the private server closed the stream; reconnecting")
            time.sleep(1)
        except (urllib.error.URLError, OSError, ValueError) as exc:
            log(f"stream lost ({exc}); reconnecting in {backoff} s")
            time.sleep(backoff)
            backoff = min(backoff * 2, 300)


if __name__ == "__main__":
    sys.exit(main())
