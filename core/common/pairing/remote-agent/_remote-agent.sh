# Shared helpers for the remote-agent shims (open-link, pbcopy, pbpaste).
# Sourced, not executed. bash 4+.

RA_SOCK="${REMOTE_AGENT_SOCK:-/run/remote-agent.sock}"
RA_TIMEOUT="${REMOTE_AGENT_TIMEOUT:-1}"

# True (0) when the agent socket is present and a stream socket.
ra_channel_available() {
    [ -S "$RA_SOCK" ]
}

# Pipe stdin to the agent socket and stream the response to stdout.
# Returns nc's exit status.
ra_send() {
    nc -U -N -w "$RA_TIMEOUT" "$RA_SOCK"
}

# Write $1 verbatim to the controlling terminal, else fd 2, else drop.
# REMOTE_AGENT_TTY overrides the target (used by tests). Uses %s, not %b:
# callers pass the output of ra_osc8/ra_osc52, which already contain raw
# escape bytes, so re-expanding here would corrupt payloads with backslashes.
ra_emit() {
    local target="${REMOTE_AGENT_TTY:-}"
    if [ -n "$target" ]; then
        printf '%s' "$1" > "$target"
        return
    fi
    if { : > /dev/tty; } 2>/dev/null; then
        printf '%s' "$1" > /dev/tty
        return
    fi
    # >&2 duplicates the already-open fd; > /dev/stderr opens a path that
    # ENXIOs in Claude Code Stop/Notification hook contexts. If fd 2 itself
    # is closed, drop silently — the BEL/link/clipboard payload has no
    # visible destination anyway.
    printf '%s' "$1" >&2 2>/dev/null || true
}

# OSC-8 hyperlink wrapping a URL, plus the plain URL, newline-terminated.
ra_osc8() {
    printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$1" "$1"
}

# OSC-52 set-clipboard escape for a base64 payload.
ra_osc52() {
    printf '\033]52;c;%s\a' "$1"
}

# ra_callback_port <url> — echo the port from a loopback `redirect_uri`
# query parameter, or nothing. Used to forward OAuth callback ports.
ra_callback_port() {
    local url="$1" enc dec rest authority host port
    case "$url" in
        *redirect_uri=*) enc="${url#*redirect_uri=}"; enc="${enc%%&*}" ;;
        *) return 0 ;;
    esac
    # URL-decode: turn %XX into \xXX, then let printf expand the bytes.
    dec="$(printf '%b' "${enc//%/\\x}")"
    rest="${dec#*://}"
    authority="${rest%%/*}"; authority="${authority%%\?*}"; authority="${authority%%#*}"
    if [ "${authority#\[}" != "$authority" ]; then          # bracketed IPv6: [::1]:port
        host="${authority%%\]*}"; host="${host#\[}"
        port="${authority##*\]:}"; [ "$port" = "$authority" ] && port=""
    else
        host="${authority%%:*}"
        port="${authority##*:}"; [ "$port" = "$authority" ] && port=""
    fi
    case "$host" in localhost|127.0.0.1|::1) ;; *) return 0 ;; esac
    case "$port" in ""|*[!0-9]*) return 0 ;; esac
    printf '%s' "$port"
}
