#!/usr/bin/env bash
# Mac-side socket handler for the remote-agent pairing bundle. Reads one request
# from stdin, dispatches the verb, writes the response to stdout. Invoked
# per-connection by launchd socket activation.
set -euo pipefail

# Sound playback config (overridable for tests / customization).
SOUNDS_DIR="${SOUNDS_DIR:-/System/Library/Sounds}"
DEFAULT_VOLUME="${DEFAULT_VOLUME:-0.5}"
AFPLAY="${AFPLAY:-afplay}"

# Which ssh Host (ControlMaster) to inject OAuth callback port forwards into.
# Set by the launchd job (EnvironmentVariables.SSH_HOST = the primary paired
# remote). Empty when no remotes are configured; FORWARD/UNFORWARD then no-op.
SSH_HOST="${SSH_HOST:-}"

IFS= read -r line || exit 0
verb="${line%% *}"
arg="${line#"$verb"}"
arg="${arg# }"   # strip the single separating space, if any

case "$verb" in
    OPEN)
        # Reject option injection: a URL never starts with '-', and open would
        # treat a leading-dash arg as an option (macOS open doesn't honor '--').
        case "$arg" in -*) printf 'ERR bad url\n' >&2; exit 1 ;; esac
        open "$arg"; printf 'OK\n'
        ;;
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
        if [ -n "$SSH_HOST" ]; then
            ssh -O forward -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
        fi
        printf 'OK\n'
        ;;
    UNFORWARD)
        case "$arg" in ""|*[!0-9]*) printf 'ERR bad port\n' >&2; exit 1 ;; esac
        if [ -n "$SSH_HOST" ]; then
            ssh -O cancel -L "$arg:127.0.0.1:$arg" -- "$SSH_HOST" >/dev/null 2>&1 || true
        fi
        printf 'OK\n'
        ;;
    *)     printf 'ERR unknown verb: %s\n' "$verb" >&2; exit 1 ;;
esac
