#!/usr/bin/env bash
# Mac-side handler for the dev-container remote agent. Reads one request
# from stdin, dispatches the verb, writes the response to stdout. Invoked
# per-connection by launchd socket activation.
set -euo pipefail

# Sound playback config (overridable for tests / customization).
SOUNDS_DIR="${SOUNDS_DIR:-/System/Library/Sounds}"
DEFAULT_VOLUME="${DEFAULT_VOLUME:-0.5}"
AFPLAY="${AFPLAY:-afplay}"

# Which ssh Host (ControlMaster) to inject port forwards into. Read from a
# config file install.sh writes, unless already set in the environment.
SSH_HOST="${SSH_HOST:-}"
if [ -z "$SSH_HOST" ]; then
    AGENT_CONF="${AGENT_CONF:-$HOME/.dev-container-agent.conf}"
    # `if` (not `&&`): a bare `[ -f x ] && .` would exit non-zero when the
    # conf is absent and abort the whole agent under `set -euo pipefail`.
    if [ -f "$AGENT_CONF" ]; then . "$AGENT_CONF"; fi
fi
SSH_HOST="${SSH_HOST:-dev-container-dev-container}"

IFS= read -r line || exit 0
verb="${line%% *}"
arg="${line#"$verb"}"
arg="${arg# }"   # strip the single separating space, if any

case "$verb" in
    OPEN)  open "$arg"; printf 'OK\n' ;;
    COPY)  pbcopy ;;     # remaining stdin is the clipboard payload
    PASTE) pbpaste ;;
    PLAY)
        read -r name volume <<< "$arg"
        sound="$SOUNDS_DIR/${name}.aiff"
        if [ -n "$name" ] && command -v "$AFPLAY" >/dev/null 2>&1 && [ -f "$sound" ]; then
            ( "$AFPLAY" -v "${volume:-$DEFAULT_VOLUME}" "$sound" >/dev/null 2>&1 & )
        else
            ( osascript -e beep >/dev/null 2>&1 & )
        fi
        printf 'OK\n'
        ;;
    FORWARD)
        case "$arg" in ""|*[!0-9]*) printf 'ERR bad port\n' >&2; exit 1 ;; esac
        ssh -O forward -L "$arg:127.0.0.1:$arg" "$SSH_HOST" >/dev/null 2>&1 || true
        printf 'OK\n'
        ;;
    UNFORWARD)
        case "$arg" in ""|*[!0-9]*) printf 'ERR bad port\n' >&2; exit 1 ;; esac
        ssh -O cancel -L "$arg:127.0.0.1:$arg" "$SSH_HOST" >/dev/null 2>&1 || true
        printf 'OK\n'
        ;;
    *)     printf 'ERR unknown verb: %s\n' "$verb" >&2; exit 1 ;;
esac
