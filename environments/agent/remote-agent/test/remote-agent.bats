#!/usr/bin/env bats

SHIMS="$BATS_TEST_DIRNAME/.."

setup() {
    SOCK="$BATS_TEST_TMPDIR/agent.sock"
    TTY_OUT="$BATS_TEST_TMPDIR/tty.out"
    : > "$TTY_OUT"
}

# Start a one-shot listener that captures the client's bytes into $1 and
# sends the contents of $2 (optional) back to the client. Waits until the
# socket is bound before returning. `3>&-` closes bats' fd 3 in the child so
# the background process doesn't hold the test runner open.
start_listener() {
    local capture="$1" response="${2:-/dev/null}"
    ( cat "$response" | nc -lU -N -w2 "$SOCK" > "$capture" 2>/dev/null ) 3>&- &
    LISTENER_PID=$!
    for _ in $(seq 1 50); do [ -S "$SOCK" ] && return 0; sleep 0.05; done
    return 1
}

# Kill + reap the listener. Safe whether or not it ever got a connection
# (a connected one-shot nc has already exited; kill is then a no-op).
stop_listener() {
    [ -n "${LISTENER_PID:-}" ] || return 0
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
    LISTENER_PID=
}

teardown() {
    stop_listener
}

@test "ra_channel_available is true when socket exists, false otherwise" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" bash -c \
        ". '$SHIMS/_remote-agent.sh'; ra_channel_available"
    [ "$status" -ne 0 ]

    start_listener "$BATS_TEST_TMPDIR/cap"
    run env REMOTE_AGENT_SOCK="$SOCK" bash -c \
        ". '$SHIMS/_remote-agent.sh'; ra_channel_available"
    [ "$status" -eq 0 ]
    stop_listener
}

@test "ra_osc8 emits an OSC-8 hyperlink wrapping the url" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_osc8 'https://x.test'"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033]8;;https://x.test'* ]]
    [[ "$output" == *"https://x.test"* ]]
}

@test "ra_osc52 emits a set-clipboard sequence with the payload" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_osc52 'aGk='"
    [ "$status" -eq 0 ]
    [[ "$output" == *$'\033]52;c;aGk='* ]]
}

@test "ra_emit writes to REMOTE_AGENT_TTY when set" {
    env REMOTE_AGENT_TTY="$TTY_OUT" bash -c ". '$SHIMS/_remote-agent.sh'; ra_emit 'hello'"
    [ "$(cat "$TTY_OUT")" = "hello" ]
}

@test "ra_emit falls back to fd 2 when no REMOTE_AGENT_TTY and no /dev/tty" {
    # setsid detaches the controlling terminal so /dev/tty becomes unopenable,
    # forcing the stderr branch. Regression for the Stop-hook ENXIO on
    # /dev/stderr — writing via >&2 must not fail.
    run setsid bash -c ". '$SHIMS/_remote-agent.sh'; ra_emit 'hello'"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "ra_emit silently no-ops when no tty and fd 2 is closed" {
    # No tty, no stderr — payload has nowhere to land. Must exit 0, not
    # surface a redirection error.
    run setsid bash -c ". '$SHIMS/_remote-agent.sh'; ra_emit 'hello' 2>&-"
    [ "$status" -eq 0 ]
}

@test "open-link sends OPEN over the channel when available" {
    start_listener "$BATS_TEST_TMPDIR/cap"
    run env REMOTE_AGENT_SOCK="$SOCK" "$SHIMS/open-link" "https://example.com"
    [ "$status" -eq 0 ]
    stop_listener
    grep -q "OPEN https://example.com" "$BATS_TEST_TMPDIR/cap"
}

@test "open-link falls back to an OSC-8 link when no channel" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" \
        REMOTE_AGENT_TTY="$TTY_OUT" "$SHIMS/open-link" "https://example.com"
    [ "$status" -eq 0 ]
    grep -qF "https://example.com" "$TTY_OUT"
    grep -qF $'\033]8;;https://example.com' "$TTY_OUT"
}

@test "open-link errors without a url argument" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" "$SHIMS/open-link"
    [ "$status" -eq 2 ]
}

@test "open-link fallback preserves backslashes verbatim (no %b expansion)" {
    # A literal backslash-n must stay two chars, not expand into a real
    # newline (which %b would do, splitting the OSC-8 sequence).
    env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" \
        REMOTE_AGENT_TTY="$TTY_OUT" "$SHIMS/open-link" 'https://x.test/a\nb'
    grep -qF 'https://x.test/a\nb' "$TTY_OUT"
    # No embedded newline: %b expansion would have introduced one.
    [ "$(wc -l < "$TTY_OUT")" -eq 0 ]
}

@test "pbcopy sends COPY + data over the channel when available" {
    start_listener "$BATS_TEST_TMPDIR/cap"
    run env REMOTE_AGENT_SOCK="$SOCK" bash -c "printf 'hello world' | '$SHIMS/pbcopy'"
    [ "$status" -eq 0 ]
    stop_listener
    # First line is the verb, remainder is the payload.
    [ "$(head -n1 "$BATS_TEST_TMPDIR/cap")" = "COPY" ]
    grep -qF "hello world" "$BATS_TEST_TMPDIR/cap"
}

@test "pbcopy falls back to OSC-52 when no channel" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" \
        REMOTE_AGENT_TTY="$TTY_OUT" bash -c "printf 'hi' | '$SHIMS/pbcopy'"
    [ "$status" -eq 0 ]
    # 'hi' base64 == 'aGk='
    grep -qF $'\033]52;c;aGk=' "$TTY_OUT"
}

@test "pbcopy sends payload byte-exact, preserving trailing newlines" {
    start_listener "$BATS_TEST_TMPDIR/cap"
    run env REMOTE_AGENT_SOCK="$SOCK" bash -c "printf 'a\n\n' | '$SHIMS/pbcopy'"
    [ "$status" -eq 0 ]
    stop_listener
    # Wire bytes must be exactly "COPY\n" (5) + "a\n\n" (3) = 8 bytes.
    [ "$(wc -c < "$BATS_TEST_TMPDIR/cap")" -eq 8 ]
}

@test "pbpaste returns the clipboard from the channel when available" {
    printf 'CLIPBOARD-CONTENT' > "$BATS_TEST_TMPDIR/resp"
    start_listener "$BATS_TEST_TMPDIR/cap" "$BATS_TEST_TMPDIR/resp"
    run env REMOTE_AGENT_SOCK="$SOCK" "$SHIMS/pbpaste"
    [ "$status" -eq 0 ]
    stop_listener
    [ "$output" = "CLIPBOARD-CONTENT" ]
    grep -q "PASTE" "$BATS_TEST_TMPDIR/cap"
}

@test "pbpaste errors with a helpful message when no channel" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" "$SHIMS/pbpaste"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no clipboard channel"* ]]
}

@test "play-sound sends PLAY name+volume over the channel" {
    start_listener "$BATS_TEST_TMPDIR/cap"
    run env REMOTE_AGENT_SOCK="$SOCK" "$SHIMS/play-sound" Morse 0.4
    [ "$status" -eq 0 ]
    stop_listener
    grep -q "PLAY Morse 0.4" "$BATS_TEST_TMPDIR/cap"
}

@test "play-sound falls back to a terminal BEL when no channel" {
    run env REMOTE_AGENT_SOCK="$BATS_TEST_TMPDIR/nope.sock" \
        REMOTE_AGENT_TTY="$TTY_OUT" "$SHIMS/play-sound" Morse 0.4
    [ "$status" -eq 0 ]
    printf '\a' > "$BATS_TEST_TMPDIR/bel"
    run cmp -s "$TTY_OUT" "$BATS_TEST_TMPDIR/bel"
    [ "$status" -eq 0 ]
}

@test "ra_callback_port extracts a loopback redirect_uri port" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_callback_port 'https://p.test/a?redirect_uri=http%3A%2F%2Flocalhost%3A40479%2Fcallback&client_id=x'"
    [ "$status" -eq 0 ]
    [ "$output" = "40479" ]
}

@test "ra_callback_port handles 127.0.0.1 and trailing param position" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_callback_port 'https://p.test/a?x=1&redirect_uri=http%3A%2F%2F127.0.0.1%3A51000%2Fcb'"
    [ "$output" = "51000" ]
}

@test "ra_callback_port ignores non-loopback redirect_uri" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_callback_port 'https://p.test/a?redirect_uri=https%3A%2F%2Fexample.com%2Fcb'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ra_callback_port ignores loopback with no port" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_callback_port 'https://p.test/a?redirect_uri=http%3A%2F%2Flocalhost%2Fcb'"
    [ -z "$output" ]
}

@test "ra_callback_port ignores a url with no redirect_uri" {
    run bash -c ". '$SHIMS/_remote-agent.sh'; ra_callback_port 'https://example.com/plain'"
    [ -z "$output" ]
}

@test "watcher sends UNFORWARD after the port stops listening" {
    python3 -m http.server 40521 --bind 127.0.0.1 >/dev/null 2>&1 &
    srv=$!
    start_listener "$BATS_TEST_TMPDIR/cap"
    REMOTE_AGENT_SOCK="$SOCK" REMOTE_AGENT_WATCH_TIMEOUT=30 "$SHIMS/remote-agent-watch-port" 40521 &
    wpid=$!
    sleep 2                       # let the watcher observe the port LISTENing
    kill "$srv" 2>/dev/null        # login "finished" — port stops listening
    wait "$wpid" 2>/dev/null || true
    stop_listener
    grep -q "UNFORWARD 40521" "$BATS_TEST_TMPDIR/cap"
}

@test "open-link forwards a loopback callback port then opens" {
    # keep-open listener captures BOTH connections (FORWARD then OPEN)
    ( nc -lU -k "$SOCK" > "$BATS_TEST_TMPDIR/cap" 2>/dev/null ) 3>&- &
    lpid=$!
    for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.05; done
    url='https://p.test/auth?redirect_uri=http%3A%2F%2Flocalhost%3A40479%2Fcallback&client_id=x'
    run env REMOTE_AGENT_SOCK="$SOCK" RA_WATCHER=/usr/bin/true "$SHIMS/open-link" "$url"
    [ "$status" -eq 0 ]
    sleep 0.3
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null || true
    grep -q "FORWARD 40479" "$BATS_TEST_TMPDIR/cap"
    grep -q "OPEN https://p.test/auth" "$BATS_TEST_TMPDIR/cap"
}

@test "open-link does not forward when redirect_uri is non-loopback" {
    ( nc -lU -k "$SOCK" > "$BATS_TEST_TMPDIR/cap" 2>/dev/null ) 3>&- &
    lpid=$!
    for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.05; done
    url='https://p.test/auth?redirect_uri=https%3A%2F%2Fexample.com%2Fcb'
    run env REMOTE_AGENT_SOCK="$SOCK" RA_WATCHER=/usr/bin/true "$SHIMS/open-link" "$url"
    [ "$status" -eq 0 ]
    sleep 0.3
    kill "$lpid" 2>/dev/null; wait "$lpid" 2>/dev/null || true
    ! grep -q "FORWARD" "$BATS_TEST_TMPDIR/cap"
    grep -q "OPEN https://p.test/auth" "$BATS_TEST_TMPDIR/cap"
}
