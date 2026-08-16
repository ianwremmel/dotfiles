#!/usr/bin/env bash
# Mac-side socket handler for the remote-agent pairing bundle. Reads one request
# from stdin, dispatches the verb, writes the response to stdout. Invoked
# per-connection by launchd socket activation.
set -euo pipefail

# Sound playback config (overridable for tests / customization).
SOUNDS_DIR="${SOUNDS_DIR:-/System/Library/Sounds}"
DEFAULT_VOLUME="${DEFAULT_VOLUME:-0.5}"
AFPLAY="${AFPLAY:-afplay}"

# Space-separated ssh Host patterns of the paired remotes, set by the launchd
# job from dotfiles.pairing.remotes. Empty when none are configured;
# FORWARD/UNFORWARD then no-op.
REMOTE_AGENT_HOSTS="${REMOTE_AGENT_HOSTS:-}"

# ssh_target [claimed-host] — print the ssh Host to inject the forward into, or
# nothing. Every remote's RemoteForward lands in this one socket and launchd
# hands us only stdin/stdout, so a request that needs a specific remote carries
# its own name; without one we fall back to the first configured pattern that is
# itself a concrete name.
#
# A claim is honored only if it matches a configured pattern. That check is the
# security boundary: the name comes from the remote and goes into ssh's argv, so
# an unchecked value could smuggle an option like -oProxyCommand=…. The
# leading-dash reject covers the case of a deliberately wide pattern.
ssh_target() {
    local claim="${1:-}" pat
    local -a pats
    case "$claim" in -*) return 0 ;; esac
    # Also guards the "${pats[@]}" expansion below: bash 3.2 (stock macOS) treats
    # an empty array as unbound under `set -u`.
    [ -n "$REMOTE_AGENT_HOSTS" ] || return 0
    # read -ra, not `for pat in $REMOTE_AGENT_HOSTS`: word-splitting an unquoted
    # expansion would also pathname-expand the patterns against the cwd.
    IFS=' ' read -ra pats <<< "$REMOTE_AGENT_HOSTS"
    for pat in "${pats[@]}"; do
        if [ -n "$claim" ]; then
            # shellcheck disable=SC2254  # $pat is a glob on purpose
            case "$claim" in $pat) printf '%s' "$claim"; return 0 ;; esac
        else
            case "$pat" in *[*?[]*) ;; ?*) printf '%s' "$pat"; return 0 ;; esac
        fi
    done
}

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
    FORWARD|UNFORWARD)
        # `FORWARD <port> [host]`; the host is optional so a remote running an
        # older shim still gets the fallback target.
        read -r port claim <<< "$arg"
        case "$port" in ""|*[!0-9]*) printf 'ERR bad port\n' >&2; exit 1 ;; esac
        target="$(ssh_target "${claim:-}")"
        if [ -n "$target" ]; then
            if [ "$verb" = FORWARD ]; then op=forward; else op=cancel; fi
            ssh -O "$op" -L "$port:127.0.0.1:$port" -- "$target" >/dev/null 2>&1 || true
        fi
        printf 'OK\n'
        ;;
    *)     printf 'ERR unknown verb: %s\n' "$verb" >&2; exit 1 ;;
esac
