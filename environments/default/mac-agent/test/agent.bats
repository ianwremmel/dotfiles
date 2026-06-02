#!/usr/bin/env bats

AGENT="$BATS_TEST_DIRNAME/../agent.sh"

# Wait up to ~2.5s for a detached player to write its log.
wait_for() { for _ in $(seq 1 50); do [ -e "$1" ] && return 0; sleep 0.05; done; return 1; }

setup() {
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN"
    # Stub open: record argv.
    cat > "$BIN/open" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$BATS_TEST_TMPDIR/open.log"
EOF
    # Stub pbcopy: record stdin.
    cat > "$BIN/pbcopy" <<EOF
#!/usr/bin/env bash
cat > "$BATS_TEST_TMPDIR/pbcopy.log"
EOF
    # Stub pbpaste: emit canned clipboard.
    cat > "$BIN/pbpaste" <<'EOF'
#!/usr/bin/env bash
printf 'STUBBED-CLIPBOARD'
EOF
    # Stub afplay: record argv.
    cat > "$BIN/afplay" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$BATS_TEST_TMPDIR/afplay.log"
EOF
    # Stub osascript: record argv.
    cat > "$BIN/osascript" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$BATS_TEST_TMPDIR/osascript.log"
EOF
    # Stub ssh: record argv.
    cat > "$BIN/ssh" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$BATS_TEST_TMPDIR/ssh.log"
EOF
    chmod +x "$BIN"/*
}

@test "OPEN dispatches to open and replies OK" {
    run env PATH="$BIN:$PATH" bash -c "printf 'OPEN https://example.com\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/open.log")" = "https://example.com" ]
}

@test "COPY pipes the remaining stdin to pbcopy" {
    run env PATH="$BIN:$PATH" bash -c "printf 'COPY\nclip me' | '$AGENT'"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/pbcopy.log")" = "clip me" ]
}

@test "PASTE returns pbpaste output" {
    run env PATH="$BIN:$PATH" bash -c "printf 'PASTE\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    [ "$output" = "STUBBED-CLIPBOARD" ]
}

@test "unknown verb exits non-zero" {
    run env PATH="$BIN:$PATH" bash -c "printf 'BOGUS x\n' | '$AGENT'"
    [ "$status" -ne 0 ]
}

@test "PLAY known sound runs afplay with file and volume" {
    run env PATH="$BIN:$PATH" bash -c "printf 'PLAY Morse 0.4\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    wait_for "$BATS_TEST_TMPDIR/afplay.log"
    [ "$(cat "$BATS_TEST_TMPDIR/afplay.log")" = "-v 0.4 /System/Library/Sounds/Morse.aiff" ]
}

@test "PLAY with no volume uses default 0.5" {
    run env PATH="$BIN:$PATH" bash -c "printf 'PLAY Morse\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    wait_for "$BATS_TEST_TMPDIR/afplay.log"
    [ "$(cat "$BATS_TEST_TMPDIR/afplay.log")" = "-v 0.5 /System/Library/Sounds/Morse.aiff" ]
}

@test "PLAY unknown sound beeps" {
    run env PATH="$BIN:$PATH" bash -c "printf 'PLAY NoSuchSound 0.4\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    wait_for "$BATS_TEST_TMPDIR/osascript.log"
    [ "$(cat "$BATS_TEST_TMPDIR/osascript.log")" = "-e beep" ]
}

@test "PLAY beeps when afplay is unavailable" {
    run env PATH="$BIN:$PATH" AFPLAY=__nonexistent__ bash -c "printf 'PLAY Morse 0.4\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    wait_for "$BATS_TEST_TMPDIR/osascript.log"
    [ "$(cat "$BATS_TEST_TMPDIR/osascript.log")" = "-e beep" ]
}

@test "FORWARD injects a LocalForward via ssh -O forward" {
    run env PATH="$BIN:$PATH" SSH_HOST=myhost AGENT_CONF=/dev/null \
        bash -c "printf 'FORWARD 40479\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/ssh.log")" = "-O forward -L 40479:127.0.0.1:40479 myhost" ]
}

@test "UNFORWARD cancels the LocalForward via ssh -O cancel" {
    run env PATH="$BIN:$PATH" SSH_HOST=myhost AGENT_CONF=/dev/null \
        bash -c "printf 'UNFORWARD 40479\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/ssh.log")" = "-O cancel -L 40479:127.0.0.1:40479 myhost" ]
}

@test "FORWARD reads SSH_HOST from the conf file" {
    echo 'SSH_HOST=confhost' > "$BATS_TEST_TMPDIR/conf"
    run env PATH="$BIN:$PATH" AGENT_CONF="$BATS_TEST_TMPDIR/conf" \
        bash -c "printf 'FORWARD 40479\n' | '$AGENT'"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/ssh.log")" = "-O forward -L 40479:127.0.0.1:40479 confhost" ]
}

@test "FORWARD rejects a non-numeric port" {
    run env PATH="$BIN:$PATH" SSH_HOST=myhost AGENT_CONF=/dev/null \
        bash -c "printf 'FORWARD notaport\n' | '$AGENT'"
    [ "$status" -ne 0 ]
}
