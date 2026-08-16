# Pairing: host patterns and multi-remote callback forwarding

`DOTFILES_REMOTE_AGENTS` names each paired remote literally, so every new agent
host needs an entry before its `remote-agent` socket channel works. The new
`claude-rc-*` fleet makes that untenable — the names are not known in advance.

Two changes: let an entry be an ssh `Host` pattern, and make the OAuth callback
forwarding verbs work for whichever remote sent the request instead of a single
primary.

## Config surface

No new knob. A pattern goes in the list that already exists:

```
DOTFILES_REMOTE_AGENTS=dev-container ai-dev-anyhook claude-rc-*
```

`lib/nix` already quotes each word into `host.remoteAgents`, and
`core/common/pairing/default.nix` already emits one `Host` block per entry, so
`Host claude-rc-*` with its `RemoteForward` falls out unchanged. Only the
`dotfiles.pairing.remotes` option description changes, to say entries are ssh
`Host` patterns.

## Fan-out skips patterns

`DOTFILES_REMOTE_AGENTS` is dual-purpose: `_dotfiles_nix_fanout` in `lib/nix`
also loops over it to `ssh <host> ./pull-and-apply` after a local apply. A
pattern is not a machine, so the loop `continue`s on any entry containing `*`,
`?`, or `[`, logging that it skipped one. `claude-rc-*` pods get dotfiles at
boot from homelab's bootstrap; there is nothing to push to.

## Wire protocol

`FORWARD <port> [host]` and `UNFORWARD <port> [host]`. The host argument is
optional so a pod running an older shim keeps working.

The Mac handler is fed by one socket that every remote's `RemoteForward` lands
in, and launchd hands it only stdin/stdout — there is no peer credential naming
the sender. The remote therefore self-identifies:
`_remote-agent.sh` gains `ra_host_id()` → `${REMOTE_AGENT_HOST_ID:-$(hostname)}`
(the env var exists for tests), which `open-link` and `remote-agent-watch-port`
append to their requests.

This resolves to a working ssh target because `ssh -O forward` recomputes
`ControlPath %C` from the name it is given, so `claude-rc-abc` finds the master
opened by `ssh claude-rc-abc` — as long as the pod's hostname matches the alias
the operator connected with.

## Mac-side target resolution

`agent.sh` replaces `SSH_HOST` with `REMOTE_AGENT_HOSTS`, the space-separated
pattern list, set by the launchd job from `cfg.remotes`. `primaryRemote`
disappears from the Nix. One resolver serves both verbs:

- A host in the request is accepted only if it glob-matches one of the
  configured patterns. This is the security boundary: the string comes from the
  remote and lands in `ssh`'s argv, so unvalidated it could be
  `-oProxyCommand=…`. Matching against the configured patterns also rejects a
  bare leading `-`.
- No host in the request → the first pattern with no glob metacharacter, which
  is today's `primaryRemote` behavior.
- Nothing resolves → no-op, as now.

## Tests and docs

`mac-agent/test/agent.bats`: retarget the two `SSH_HOST` tests to
`REMOTE_AGENT_HOSTS`; delete the `AGENT_CONF` test, which exercises a mechanism
`agent.sh` does not have and fails today; add cases for a glob-matched host
accepted, an unmatched host rejected, `-oProxyCommand=…` rejected, and an
omitted host falling back.

`remote-agent/test/remote-agent.bats`: the `FORWARD`/`UNFORWARD` line assertions
gain the host id.

Docs: the `DOTFILES_REMOTE_AGENTS` entry in `framework/CLAUDE.md` and the
`common/pairing` paragraph in `core/CLAUDE.md`.
