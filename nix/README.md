# Nix-managed dotfiles (slice)

This directory is a [Nix flake](https://nixos.wiki/wiki/Flakes) that manages a
growing slice of the dotfiles via [home-manager](https://github.com/nix-community/home-manager),
activated automatically by the `nix` plugin during `./apply`.

## Background

The repo is mid-migration from the homegrown plugin framework toward Nix. See
`docs/superpowers/specs/2026-05-22-nix-migration-design.md` for the design and
planned phases. So far this manages: `bat` (shared in the `all` layer); `ripgrep` (in the `default` profile); the full git config (aliases, body, identity, includes) via `programs.git` plus a one-time activation that retires the legacy rsync-managed `~/.gitconfig`; commit signing — `programs.gpg` + `services.gpg-agent` with per-OS pinentry (`pinentry-mac` on macOS, `pinentry-tty` on Linux), `programs.git.settings.user.signingkey` + `commit.gpgsign` in the `default` profile, and a one-time activation that retires the old plugin-written `~/.gnupg/*.conf`; and shell config — bash and zsh via `programs.bash` + `programs.zsh` (with the prior `.zshrc.d/` and `.bash_profile.d/` modular content folded into the relevant typed options), `.inputrc` via `home.file`, and one-time activations that retire the rsync-managed shell dotfiles plus the `shells` plugin's chsh / /etc/shells logic. See Profiles for the layering and Migrating a private custom environment for the private-side migration steps.

## Install

`./apply` runs the `nix` plugin, which installs Nix if absent and builds and
activates `homeConfigurations."<profile>@<system>"` for the current machine
(or a private-flake config if one is set up — see Profiles). The flake
supports `aarch64-darwin`, `x86_64-darwin`, `x86_64-linux`, and
`aarch64-linux`.

- **macOS:** the full framework runs; Nix is installed via the Determinate
  Systems installer (daemon-based — macOS SIP requires it).
- **Linux:** `./apply` runs only the nix step (the macOS-only plugins are
  skipped). Nix is installed single-user with no daemon via the official
  installer.

To build/activate by hand after Nix is installed:

    flags="--extra-experimental-features 'nix-command flakes'"
    out="$(mktemp -d)/result"
    sys="$(nix $flags eval --impure --raw --expr builtins.currentSystem)"
    profile="${DOTFILES_ENVIRONMENT:-default}"
    nix $flags build "path:$PWD#homeConfigurations.\"${profile}@${sys}\".activationPackage" --out-link "$out"
    "$out/activate"

(On a fresh Linux single-user install flakes are not enabled by default, hence
the `--extra-experimental-features` flag.)

## Usage

Edit `home.nix` to add packages (`home.packages`) or program modules
(`programs.*`), then re-run `./apply` (or the manual build/activate above).

## Profiles

Per-machine profiles select which extra modules layer on top of the shared
base. Selection reuses the framework's `DOTFILES_ENVIRONMENT` value — no new
variable — and is loaded the same way on both platforms (`./apply` runs
`environment_get_current` + `config_load` from the framework). The
plugin-generated `nix/host.nix` carries both `username` and `profile`.

### Public profiles and layers

`nix/home.nix` is infrastructure (username, homeDirectory, stateVersion,
`programs.home-manager.enable`). `lib.mkHome` always composes it with the
**always-included `all` layer** (shared content every machine gets), plus
whichever selectable profile is active:

- `all` — always included via `mkHome`; shared content for every machine
  regardless of profile or private overlay (currently `bat`, the shared
  git config — aliases, body, includes — via `programs.git`, GPG/agent
  setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on
  Linux, AND bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`).
- `default` — selectable profile; matches the framework's default
  `DOTFILES_ENVIRONMENT=default` and adds `ripgrep`.
- `agent` — selectable profile for headless / agent boxes; lean.

The public flake exposes them as a module library
(`homeModules.{base,all,default,agent}` + a `lib.mkHome` helper) and as
ready-made `homeConfigurations."<profile>@<system>"` outputs (one per
selectable profile × system). When no private flake matches the active
profile, the plugin builds the matching public config directly.

### Private profiles

Private/sensitive profiles live in your separate `custom_environments/` repo
as **flakes** at `custom_environments/<env>/nix/flake.nix`. The private flake
consumes the public flake as an input, composes on top of it, and exposes
`homeConfigurations."<system>"` (one per supported system; no profile prefix
because the env is implicit in the flake's location).

**Two things to know before authoring one:**

1. **`path:` flake refs require git-tracked files.** When the `nix` plugin
   builds your private flake, it uses `path:custom_environments/<env>/nix`.
   Because that path lives inside a git repo (typically your private
   `custom_environments` repo set up by `framework/customize`), Nix's path
   fetcher applies git-tree semantics — only files tracked in that repo are
   visible. **Commit your private flake files** to your private repo before
   the first `./apply`. (For one-off throwaway testing without the private
   repo, `git init` inside `custom_environments/<env>/nix/` and commit the
   files there works.)
2. **Override public option values with `lib.mkForce`.** If you set an option
   that a layer below (base, `all`, or the public profile you imported) already
   set to a different scalar value, wrap your value with `lib.mkForce`.
   Without it, home-manager's module system reports a conflict. (Example: the
   `all` layer sets `programs.bat.config.theme = "ansi"`; a private profile
   that wants a different theme uses `lib.mkForce "<other-theme>"`.)

Template:

    {
      description = "Private profile for <env>";

      inputs = {
        # Default points at the published public repo so `nix flake check`
        # works in this private repo standalone. The dotfiles `nix` plugin
        # overrides this to a local `path:` at apply time, so day-to-day
        # builds use whatever local public source is current — including
        # its untracked host.nix.
        public.url = "github:ianwremmel/dotfiles?dir=nix";
        nixpkgs.follows      = "public/nixpkgs";
        home-manager.follows = "public/home-manager";
      };

      outputs = { self, public, ... }:
        let
          host = import (public + "/host.nix");
          supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];
          mkConfig = system: public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.default
              ./work.nix
            ];
          };
        in {
          homeConfigurations = builtins.listToAttrs (map
            (system: { name = system; value = mkConfig system; })
            supportedSystems);
        };
    }

Where `./work.nix` (or any name) is a normal home-manager module living
alongside `flake.nix` and may import siblings. Example override of a public
option:

    # ./work.nix
    { lib, pkgs, ... }: {
      # Override the bat theme that `all` sets, and add work-specific tools.
      programs.bat.config.theme = lib.mkForce "Coldark-Dark";
      home.packages = [ pkgs.awscli2 ];
      # …more work-specific modules.
    }

The private flake also has its own `flake.lock` (committed to your private
repo) for standalone reproducibility.

### Migrating a private custom environment after this slice

When a slice migrates a plugin or rsync-managed file into home-manager,
machines using a private `custom_environments/<env>/` repo need a one-time
update: the old rsync-managed file gets superseded by the home-manager-managed
XDG file, and any per-env overrides that used to live in the rsync'd file
move into the private flake.

For the git slice (`git` plugin + the rsync'd `.gitconfig` body):

1. **Update your private flake** to add `programs.git`:

       { lib, pkgs, ... }: {
         programs.git.settings = {
           user = {
             name  = lib.mkForce "<your name for this env>";
             email = lib.mkForce "<your email for this env>";
           };

           # Any env-specific git settings that used to live in your private
           # .gitconfig — enterprise hosts, additional aliases, etc.
           # Aliases land under `settings.alias`; raw git config sections
           # become other top-level `settings.*` attrs. Use `lib.mkForce`
           # only where overriding a value the public layer set.
           # …your env's settings here…
         };
       }

2. **Delete the rsync'd .gitconfig source from your private repo:**
   `git rm custom_environments/<env>/home/.gitconfig` in the private repo
   and commit. home-manager will own `~/.config/git/config` on that machine
   after the next `./apply`, so the rsync source is no longer needed.

3. **First `./apply` after this slice** runs the
   `migrateLegacyGitConfig` activation script, which moves any pre-existing
   `~/.gitconfig` aside to `~/.gitconfig.legacy-backup` once. No action
   needed; mentioned so you know what the file is if you see it. You can
   `rm ~/.gitconfig.legacy-backup` whenever you're satisfied with the
   migration.

For the commit-signing slice (`commit_signing` plugin retired;
`programs.gpg`, `services.gpg-agent`, and
`programs.git.settings.{user.signingkey,commit.gpgsign}` take over):

1. **Update your private flake** to override the signing key
   (and explicitly set `commit.gpgsign` if your private flake
   doesn't import `public.homeModules.default`):

       { lib, pkgs, ... }: {
         programs.git.settings = {
           user.signingkey = lib.mkForce "<your env's key id>";
           # commit.gpgsign already inherited from `default` if your
           # private flake imports `public.homeModules.default`;
           # otherwise:
           # commit.gpgsign = lib.mkForce true;
         };
       }

2. **Nothing to delete from your private repo this time.** The old
   `commit_signing` plugin lived only in the public repo (no rsync
   source under `custom_environments/<env>/home/`).

3. **First `./apply` after this slice** runs the
   `migrateLegacyGnupgConfig` activation script, which moves any
   pre-existing real `~/.gnupg/gpg.conf` and `~/.gnupg/gpg-agent.conf`
   aside to `.legacy-backup` siblings once. No action needed; `rm ~/.gnupg/gpg.conf.legacy-backup ~/.gnupg/gpg-agent.conf.legacy-backup` when satisfied. Your actual keyring (`pubring.kbx`,
   `private-keys-v1.d/`, `trustdb.gpg`, etc.) is never touched.

For the shells slice (`shells` plugin retired; all rsync-managed shell
dotfiles migrated; `programs.bash`, `programs.zsh`, `home.file.".inputrc"`
and two activation scripts take over):

1. **Update your private flake** to append work-specific shell content
   (extra PATH entries, env vars, tooling init shell hooks) via the
   `lines`-typed `*Extra` options. These CONCATENATE across layers — no
   `lib.mkForce` needed:

       { lib, pkgs, ... }: {
         programs.zsh.initContent = ''
           # work-specific zsh init: extra PATH entries, tooling init, …
         '';
         programs.bash.profileExtra = ''
           # work-specific bash profile init: same idea
         '';
         home.sessionVariables = {
           # work-specific cross-shell env vars (no overlap with public ones)
         };
       }

2. **Delete the now-orphaned rsync sources** from your private repo:

       git rm custom_environments/<env>/home/.zshrc \
              custom_environments/<env>/home/.zshenv \
              custom_environments/<env>/home/.zprofile \
              custom_environments/<env>/home/.bash_profile \
              custom_environments/<env>/home/.bashrc \
              custom_environments/<env>/home/.profile \
              custom_environments/<env>/home/.inputrc
       git rm -r custom_environments/<env>/home/.zshrc.d \
                 custom_environments/<env>/home/.bash_profile.d
       git commit -m "remove rsync'd shell config (now managed via nix)"

3. **First `./apply` after this slice** runs the `migrateLegacyShellConfig`
   activation, which moves any pre-existing real shell dotfiles aside to
   `.legacy-backup` siblings once, AND `chshAndEtcShells` activation, which
   registers `~/.nix-profile/bin/zsh` in `/etc/shells` and chshes the user
   to it (interactive sudo + password prompts in the apply terminal). The
   second activation is interactive-tty-aware — it skips on container
   builds and leaves its marker absent so a later interactive apply can
   complete it. You can `rm ~/.{zshrc,zshenv,zprofile,bash_profile,bashrc,
   profile,inputrc}.legacy-backup` and `rm -rf ~/.{zshrc,bash_profile}.d.
   legacy-backup` whenever you're satisfied with the migration.

The same shape applies to future slices that migrate a plugin or rsync
source: add the new options to your private flake, delete the now-orphaned
rsync source from your private repo, and trust the activation cleanup.

## Backout

- **Disable the slice:** set `DOTFILES_NIX_SKIP=1` before `./apply`.
- **Drop a managed file:** remove its lines from `home.nix` and re-activate;
  home-manager removes only symlinks it created.
- **Remove Nix entirely:** delete `plugins/nix/` and `nix/`, then uninstall Nix:
  - **macOS** (Determinate): `/nix/nix-installer uninstall`.
  - **Linux** (official single-user): `nix-env --uninstall nix`, then
    `rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels /nix` and remove the
    nix lines from your shell rc.

## License

Same as the parent dotfiles repository.
