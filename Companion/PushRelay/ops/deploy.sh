#!/usr/bin/env bash
# Idempotent, isolated deploy for the self-hosted push relay.
#
# It only ever writes to push-relay-specific paths and only ever acts on the
# iterm2-push-relay systemd unit — it NEVER touches the companion relay
# (iterm2-companion-relay-cf) or the dashboard (iterm2-relay-dashboard), their
# /opt copies, env files, or state. A guard below aborts if the target paths
# don't look push-relay-specific, so a bad edit can't point it at the relay.
#
# Safe to re-run: code + unit are refreshed every time; an EXISTING env file or
# .p8 credential is never overwritten (they hold real secrets). The service is
# only STARTED once its config is actually in place — otherwise it's installed
# and left stopped with instructions, so it can't crash-loop on missing config.
#
# Usage:
#   ./ops/deploy.sh                       # deploy code + unit; start if configured
#   APNS_P8_SRC=~/AuthKey_ABC123.p8 ./ops/deploy.sh   # also install the signing key
#
# Needs sudo for /opt, /etc, and systemctl (it prompts). Run as your normal
# user, not root.

set -euo pipefail

# --- Fixed, push-relay-only targets -----------------------------------------
UNIT="iterm2-push-relay"
OPT_DIR="/opt/${UNIT}"
ETC_ENV="/etc/${UNIT}.env"
CRED_DIR="/etc/${UNIT}"
CRED_P8="${CRED_DIR}/apns.p8"
UNIT_FILE="/etc/systemd/system/${UNIT}.service"
HEALTH_PORT="${PUSH_PORT:-8790}"

# Self-locate: this script lives in <PushRelay>/ops, so the source root is its
# parent. Everything is copied FROM here.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$(dirname "$SCRIPT_DIR")"

# --- Safety guard: never target companion/dashboard paths -------------------
for p in "$OPT_DIR" "$ETC_ENV" "$CRED_DIR" "$UNIT_FILE"; do
  case "$p" in
    *iterm2-push-relay*) : ;;   # ok
    *) echo "ABORT: refusing to write non-push-relay path: $p" >&2; exit 2 ;;
  esac
done
if [[ "$UNIT" == *companion* || "$UNIT" == *dashboard* ]]; then
  echo "ABORT: unit name '$UNIT' is not push-relay-specific" >&2; exit 2
fi

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# --- Preflight ---------------------------------------------------------------
[[ -f "$SRC/bin/push-relay.js" ]] || { echo "ABORT: run from the PushRelay checkout ($SRC/bin/push-relay.js missing)" >&2; exit 1; }

# Port must be free OR already ours. If something else holds it, stop — do not
# fight the companion relay (8788) / dashboard (8789).
if ss -tln 2>/dev/null | grep -q "127.0.0.1:${HEALTH_PORT} "; then
  if ! systemctl is-active --quiet "$UNIT" 2>/dev/null; then
    echo "ABORT: 127.0.0.1:${HEALTH_PORT} is in use by something other than $UNIT" >&2
    exit 1
  fi
fi

# --- 1. Runtime code into /opt (gnachman-owned, like the companion copy) -----
say "Installing code to $OPT_DIR"
if [[ ! -d "$OPT_DIR" ]]; then
  sudo mkdir -p "$OPT_DIR"
  sudo chown "$(id -un):$(id -gn)" "$OPT_DIR"
fi
# Copy only the runtime files (never node_modules or the repo's git/test cruft).
cp -r "$SRC/bin" "$SRC/host" "$SRC/src" "$SRC/package.json" "$SRC/package-lock.json" "$OPT_DIR/"

say "Installing production deps (builds better-sqlite3)"
( cd "$OPT_DIR" && npm ci --omit=dev )

# --- 2. APNs signing key credential (never clobber an existing one) ----------
if [[ -n "${APNS_P8_SRC:-}" ]]; then
  [[ -f "$APNS_P8_SRC" ]] || { echo "ABORT: APNS_P8_SRC=$APNS_P8_SRC not found" >&2; exit 1; }
  say "Installing APNs signing key -> $CRED_P8"
  sudo mkdir -p "$CRED_DIR"
  sudo install -m 0600 "$APNS_P8_SRC" "$CRED_P8"
elif sudo test -f "$CRED_P8"; then
  say "APNs signing key already present at $CRED_P8 (leaving as-is)"
else
  say "No APNs signing key yet (set APNS_P8_SRC=... to install one)"
fi

# --- 3. EnvironmentFile (install template once; never overwrite real config) -
if sudo test -f "$ETC_ENV"; then
  say "Env file already present at $ETC_ENV (leaving as-is)"
else
  say "Installing env template -> $ETC_ENV (EDIT IT: APNS_TEAM_ID / APNS_KEY_ID / APNS_TOPIC)"
  sudo install -m 0600 "$SRC/ops/push-relay.env.example" "$ETC_ENV"
fi

# --- 4. systemd unit ---------------------------------------------------------
say "Installing unit -> $UNIT_FILE"
sudo cp "$SRC/ops/${UNIT}.service" "$UNIT_FILE"
sudo systemctl daemon-reload
sudo systemctl enable "$UNIT" >/dev/null

# --- 5. Start only if actually configured; else stop-and-instruct -----------
configured=1
sudo test -f "$CRED_P8" || configured=0
if sudo grep -qE '^APNS_TEAM_ID=XXXXXXXXXX$' "$ETC_ENV" 2>/dev/null; then configured=0; fi
if sudo grep -qE '^APNS_KEY_ID=YYYYYYYYYY$'  "$ETC_ENV" 2>/dev/null; then configured=0; fi

if [[ "$configured" == 1 ]]; then
  say "Config present — (re)starting $UNIT"
  sudo systemctl restart "$UNIT"
  # Health check on loopback (no reverse proxy involved).
  ok=0
  for _ in 1 2 3 4 5; do
    if curl -fs -o /dev/null -X POST "127.0.0.1:${HEALTH_PORT}/register" -d '{}' 2>/dev/null \
       || curl -s "127.0.0.1:${HEALTH_PORT}/nope" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done
  reply="$(curl -s -X POST "127.0.0.1:${HEALTH_PORT}/nope" -d '{}' 2>/dev/null || true)"
  if [[ "$ok" == 1 && "$reply" == *"no such endpoint"* ]]; then
    say "HEALTHY: $UNIT is serving on 127.0.0.1:${HEALTH_PORT}  ($reply)"
  else
    echo "WARNING: started but health check did not confirm. Check: sudo journalctl -u $UNIT -n 50" >&2
    exit 1
  fi
else
  sudo systemctl stop "$UNIT" 2>/dev/null || true
  cat <<EOF

==> Installed but NOT started (config incomplete). To finish:
    1. sudo \$EDITOR $ETC_ENV        # set APNS_TEAM_ID / APNS_KEY_ID / APNS_TOPIC
    2. APNS_P8_SRC=/path/to/AuthKey.p8 ./ops/deploy.sh   # install the key + start
       (or: sudo install -m600 key.p8 $CRED_P8 && sudo systemctl start $UNIT)

Nothing touching the companion relay or dashboard was changed.
EOF
fi
