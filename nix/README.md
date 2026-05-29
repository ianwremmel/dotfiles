# Nix-managed dotfiles (slice)

This directory is a [Nix flake](https://nixos.wiki/wiki/Flakes) that manages a
growing slice of the dotfiles via [home-manager](https://github.com/nix-community/home-manager),
activated automatically by the `nix` plugin during `./apply`.

## Background

The repo is mid-migration from the homegrown plugin framework toward Nix. See
`docs/superpowers/specs/2026-05-22-nix-migration-design.md` for the design and
planned phases. So far this manages: the full git config (aliases, body, identity, includes) via `programs.git` plus a one-time activation that retires the legacy rsync-managed `~/.gitconfig`; commit signing — `programs.gpg` + `services.gpg-agent` with per-OS pinentry (`pinentry-mac` on macOS, `pinentry-tty` on Linux), `programs.git.settings.user.signingkey` + `commit.gpgsign` in the `default` profile, and a one-time activation that retires the old plugin-written `~/.gnupg/*.conf`; and shell config — bash and zsh via `programs.bash` + `programs.zsh` (with the prior `.zshrc.d/` and `.bash_profile.d/` modular content folded into the relevant typed options), `.inputrc` via `home.file`, and one-time activations that retire the rsync-managed shell dotfiles plus the `shells` plugin's chsh / /etc/shells logic; and a prompt — starship via `programs.starship` (replacing the retired `powerlevel` plugin and its rsync'd `.p10k.zsh`); and Node.js — fnm via `pkgs.fnm` + shell init injection (replacing the retired `nvm` and `node` plugins), with a one-time activation that installs the LTS version on first apply; and CLI tools — most brew formulas migrated to `home.packages` (a handful of escape-hatched formulas without nix equivalents stay as `homebrew.brews` in nix-darwin); and a system-level layer via nix-darwin managing brew casks (including a Nerd Font for starship), mas-installed apps (including Xcode), the login-shell declaration, and Xcode license acceptance. See Profiles for the layering and Migrating a private custom environment for the private-side migration steps.

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
  regardless of profile or private overlay (currently the shared
  git config — aliases, body, includes — via `programs.git`, GPG/agent
  setup with per-OS pinentry: `pinentry-mac` on macOS, `pinentry-tty` on
  Linux, bash + zsh via `programs.bash` + `programs.zsh` plus `.inputrc` via `home.file`, AND starship as the prompt, AND fnm for Node.js version management, AND a curated set of CLI tools via `home.packages`, AND a system-level layer via nix-darwin managing brew casks (a Nerd Font included), mas apps (including Xcode), the login shell declaration, and Xcode license acceptance).
- `default` — selectable profile; matches the framework's default
  `DOTFILES_ENVIRONMENT=default` and adds personal-machine CLI tools
  (cloud tooling, scripting languages, kubernetes utilities) via
  `nix/profiles/default/cli-tools.nix`.
- `agent` — selectable profile for headless / agent boxes; lean.

The public flake exposes them as a module library
(`homeModules.{base,all,default,agent}` + a `lib.mkHome` helper) and as
ready-made `homeConfigurations."<profile>@<system>"` outputs (one per
selectable profile × system). When no private flake matches the active
profile, the plugin builds the matching public config directly.

### Darwin configurations (macOS system layer)

In addition to home-manager (user-level), this flake exposes
`darwinConfigurations.<profile>@<system>` outputs (system-level, macOS-only)
via nix-darwin. The active profile selects which module from
`nix/darwin/<profile>/` is included alongside the universal `nix/darwin/base.nix`.

Currently only `default` has a darwin module (`nix/darwin/default/homebrew.nix`).
The `agent` profile is Linux-only and has no darwin counterpart.

System-level concerns owned by nix-darwin (not home-manager):

- Homebrew casks, mas apps, and escape-hatched brews — `homebrew.{casks,masApps,brews}`
- Login shell declaration — `users.users.<name>.shell` + `environment.shells`
- System PATH baseline including `/opt/homebrew/{bin,sbin}` — `environment.systemPath`
- Xcode license acceptance — `system.activationScripts.xcodeLicense`

Note: `nix.enable = false` in the base config — Determinate's nix installer
manages its own daemon and refuses to coexist with nix-darwin's native nix
management. nix-darwin still does everything else.

nix-darwin activations are sudo-required and managed by the `nix` plugin
(macOS-only branch). On a fresh machine the plugin auto-bootstraps via
`sudo -H nix run nix-darwin -- switch …`; on subsequent applies it uses
`sudo -H darwin-rebuild switch …`.

### Private profiles

Private/sensitive profiles live in your separate `custom_environments/` repo
as **flakes** at `custom_environments/<env>/nix/flake.nix`. The private flake
consumes the public flake as an input, composes on top of it, and exposes
`homeConfigurations."<system>"` (one per supported system; no profile prefix
because the env is implicit in the flake's location).

**Two things to know before authoring one:**

1. **`path:` flake refs require git-tracked files.** When `lib/nix`
   builds your private flake, it uses `path:custom_environments/<env>/nix`.
   Because that path lives inside a git repo (typically your private
   `custom_environments` repo, cloned manually into `custom_environments/`),
   Nix's path fetcher applies git-tree semantics — only files tracked in that
   repo are visible. **Commit your private flake files** to your private repo before
   the first `./apply`. (For one-off throwaway testing without the private
   repo, `git init` inside `custom_environments/<env>/nix/` and commit the
   files there works.)
2. **Override public option values with `lib.mkForce`.** If you set an option
   that a layer below (base, `all`, or the public profile you imported) already
   set to a different scalar value, wrap your value with `lib.mkForce`.
   Without it, home-manager's module system reports a conflict. (Example: the
   `all` layer sets `programs.starship.settings = { };` (opt in to defaults);
   a private profile that wants a custom starship layout uses
   `programs.starship.settings = lib.mkForce { add_newline = false; … };`.)

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
      # Override the empty starship settings that `all` sets, and add
      # work-specific tools.
      programs.starship.settings = lib.mkForce { add_newline = false; };
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

For the prompt slice (`powerlevel` plugin retired; `.p10k.zsh` dropped;
starship via `programs.starship.enable` takes over):

1. If your private flake had a `custom_environments/<env>/home/.p10k.zsh`
   override (none in the public template), `git rm` it from your private
   repo and commit. Starship reads no such file; the rsync source is
   orphaned.

2. To customize starship per-environment, add to your private flake:

       { lib, pkgs, ... }: {
         programs.starship.settings = lib.mkForce {
           # …your starship.toml content as a Nix attrset…
         };
       }

   Use `lib.mkForce` because the public profile sets `settings = { };` —
   the typed attrset would conflict without it. Alternatively, use
   `lib.recursiveUpdate` if you want to merge with potential future
   public defaults.

3. **First `./apply` after this slice** runs `migrateLegacyP10kConfig`,
   which moves any pre-existing `~/.p10k.zsh` aside to
   `~/.p10k.zsh.legacy-backup`. The cloned `~/powerlevel10k/` repo is
   left in place (228-entry inert directory); `rm -rf ~/powerlevel10k`
   when satisfied. You can also `rm ~/.p10k.zsh.legacy-backup` whenever
   you're done with the migration.

For the nodejs slice (`nvm` and `node` plugins retired; fnm via
`home.packages = [ pkgs.fnm ]` + inline `eval "$(fnm env --use-on-cd --shell …)"`
in the bash/zsh init blocks; `home.activation.installFnmDefaultNode`
auto-installs the LTS node on first apply):

1. **No private flake changes needed** unless you want a different node
   version or different fnm behavior. home-manager 26.05 does NOT ship a
   typed `programs.fnm` module, so per-environment overrides are done by
   extending the same `home.packages` and shell-init blocks the public
   layer uses:

       { lib, pkgs, ... }: {
         # To use a different fnm build (e.g., a pinned version), add the
         # package and your own init lines; the public layer's defaults
         # still apply unless you remove them.
         home.packages = [ pkgs.fnm ];

         # To override the `--use-on-cd` behavior or use a different
         # `nodeDistMirror`, set FNM_NODE_DIST_MIRROR before the init line
         # via programs.zsh.envExtra / programs.bash.profileExtra:
         programs.zsh.envExtra = ''
           export FNM_NODE_DIST_MIRROR="https://your.mirror/dist/"
         '';
       }

2. **Optional cleanup after first apply:**

       rm -rf ~/.nvm           # the cloned nvm repo + installed node versions
       brew uninstall jq       # if you don't otherwise need jq

3. **To upgrade past the originally-installed LTS** (when Node 26
   becomes LTS, etc.):

       rm ~/.fnm-default-node.hm-migrated
       ./apply
       # OR interactively:
       fnm install --lts
       fnm default lts-latest

4. **To pin a different default version per environment**, post-apply:

       fnm install <version>
       fnm default <version>

   The marker file prevents the activation from re-overriding this.

For the brew-formulas slice (most CLI formulas migrated from Brewfiles to
`home.packages` via `nix/profiles/{all,default}/cli-tools.nix`; casks,
mas, and taps subsequently moved to nix-darwin's `homebrew.*` options
in the following slice):

1. **Update your private flake** to add any of YOUR brew formulas that
   have nix equivalents to `home.packages` in a private module:

       { pkgs, ... }: {
         home.packages = with pkgs; [
           # …your private CLI tools…
         ];
       }

2. **Delete the corresponding `brew '<name>'` lines** from your private
   Brewfile. Keep cask, mas, and tap entries (those move in the nix-darwin
   slice — see that slice's sub-block below).

3. **First `./apply` after this slice** runs the brew step against your
   slimmed Brewfile; `brew bundle cleanup --force` uninstalls the formulas
   that no longer appear there, and the nix-installed versions take over
   via PATH precedence.

4. **Formulas without a nix equivalent** (e.g., custom-tap formulas from
   work-specific taps) STAY in your private Brewfile until the nix-darwin
   slice (next), which adds `homebrew.brews` as a declarative way to manage
   these.

5. **`bat` and `ripgrep` were proof-of-concept demo packages** added in
   the first nix slices to prove the migration was working. They're
   removed in this slice. If you actually want either, add them to
   `nix/profiles/<profile>/cli-tools.nix` (or your private flake) as
   ordinary `home.packages` entries.

For the nix-darwin slice (homebrew + system-level state move into
nix-darwin; bash plugins retire):

1. **Bootstrap nix-darwin on each macOS machine** (one-time). The first
   `./apply` after this slice detects `darwin-rebuild` is absent and
   bootstraps automatically (sudo required; the framework's keep-alive
   covers it). If running outside `./apply`:

       sudo -H nix run nix-darwin -- switch --flake "path:$PWD/nix#default@aarch64-darwin"

   Subsequent applies use `sudo -H darwin-rebuild switch --flake …`
   automatically via the nix plugin. Note: if `/etc/shells` already
   exists with non-nix-darwin content (e.g., from slice 6's
   chshAndEtcShells activation), nix-darwin refuses to overwrite it.
   Rename it once: `sudo mv /etc/shells /etc/shells.before-nix-darwin`
   and re-run `./apply`. If you use Determinate's nix installer (the
   default on this repo), the base config has `nix.enable = false`
   already so nix-darwin doesn't try to manage the Nix daemon.

2. **Private darwin profiles are not wired up yet.** The `nix` plugin
   always builds nix-darwin from the public flake
   (`darwinConfigurations.<profile>@<system>`); it does not yet check for
   a per-env private darwin flake the way it does for home-manager. And
   with the bash `homebrew` plugin retired, nothing in the framework
   consumes a `Brewfile` anymore — your private
   `custom_environments/<env>/Brewfile` is inert. Until a follow-up slice
   adds the private-darwin branch:

   - Personal-machine casks/mas/brews already live in
     `nix/darwin/default/homebrew.nix` (public). Add additional ones
     there if they're not sensitive.
   - Sensitive or work-specific casks/mas/brews have NO declarative path
     yet. Options: install them imperatively after `./apply` (knowing the
     next apply's `cleanup = "uninstall"` will remove them again), keep
     them as uncommitted local edits in `nix/darwin/<profile>/`, or wait
     for the follow-up slice. `homebrew.onActivation.cleanup = "uninstall"`
     in `nix/darwin/base.nix` removes any brew package not declared in
     `homebrew.{casks,brews,masApps}` — there is no Brewfile escape hatch
     anymore.

3. **The `chshAndEtcShells` activation from slice 6 is gone.** nix-darwin's
   `users.users.<name>.shell` + `environment.shells` handle login-shell
   selection declaratively. No marker file; no interactive prompt. The
   `~/.shells-chsh.hm-migrated` marker on existing machines is harmless
   leftover state; you can `rm` it if you want.

4. **Xcode license** is accepted automatically via
   `system.activationScripts.xcodeLicense`. The Xcode app itself
   installs via `homebrew.masApps.Xcode = 497799835;` in
   `nix/darwin/base.nix`. `mas` is declared in `homebrew.brews` to
   prevent the cleanup policy from removing it (nix-darwin doesn't
   add `mas` implicitly as a `masApps` dependency).

5. **Set iTerm's font** manually to "MesloLGS Nerd Font" once after
   the cask installs: iTerm → Settings → Profiles → Text → Font.
   Same for Terminal.app if you use it. The slice-11 declarative pin
   (`com.googlecode.iterm2`/`com.apple.terminal` in `nix/darwin/defaults.nix`)
   writes a plain-string font name, but both apps store fonts as
   binary-encoded `NSFont` data and ignore the string form. The Nerd
   Font cask installs to `~/Library/Fonts/` (user-level), not
   `/Library/Fonts/`; both are visible to apps.

For the nix-firstrun slice (`firstrun` plugin retired; macOS `defaults` writes migrated to nix-darwin's `system.defaults` + `CustomUserPreferences` + activation scripts):

This slice migrates `environments/all/firstrun` (the macOS preferences script)
into nix-darwin's declarative system layer. The bash framework's `firstrun`
plugin is fully retired.

**One-time apply notes:**

- Mail, Safari, Messages, Photos, Activity Monitor, Address Book, Calendar,
  Contacts, and iCal may need a one-time relaunch after this slice's first
  `./apply` for their new preferences to take effect. nix-darwin already
  kicks `cfprefsd`, `Dock`, `SystemUIServer`, and `Finder` automatically.

- The `FIRSTRUN_APPLIED=1` entry in your `~/.dotfilesrc` is now vestigial and
  is automatically removed by a home-manager activation on next `./apply`.
  The rest of your config file is untouched.

- iTerm and Terminal.app store font preferences as binary-encoded `NSFont`
  data, not plain strings. The slice writes a plain-string `Normal Font` value
  to `com.googlecode.iterm2` via `CustomUserPreferences`, but this does NOT
  control what iTerm or Terminal.app actually use on launch (confirmed empirically).
  The keys are preserved as a placeholder. Set the font manually: iTerm/Terminal
  → Settings → Profiles → Text → Font → "MesloLGS Nerd Font". A follow-up slice
  could capture the binary `NSFont` bytes from a working machine and write them
  via `defaults write -data` to close this for real.

- Contacts.app name-display preferences (`ABNameDisplay`, `ABNameSortingFormat`)
  are NOT declaratively managed. macOS's TCC system blocks scripted writes
  to `com.apple.addressbook` from nix-darwin's activation context. If you
  want last-name-first sorting, set it manually in Contacts → Settings →
  General.

**Private flake update (only if you have one):**

If your private flake extends `darwinConfigurations` with additional
`system.defaults.*` or `CustomUserPreferences` entries, no changes are
required — Nix module merging handles additive private prefs on top of the
public baseline. If your private flake conflicts with a key set in the
public `nix/darwin/defaults.nix`, override it with `lib.mkForce` in the
private module.

For the nix-vim slice (`vim` plugin retired; `~/.vimrc` content + plugins now home-manager managed via `programs.vim`):

This slice migrates the bash `vim` plugin (which `git clone`d three pathogen
bundles at apply time) and the rsynced `~/.vimrc` + `~/.vim/` content into
home-manager's `programs.vim`. Plugins now come from nixpkgs at build time:
`vim-javascript` (pangloss — replaces unmaintained `jelera/vim-javascript-syntax`),
`vim-colors-solarized`, `editorconfig-vim`. Pathogen is no longer used; vim's
native `packpath` mechanism handles plugin loading.

home-manager's `programs.vim` does NOT create `~/.vimrc` or `~/.vim/vimrc`.
The vimrc body lives inside the Nix store, and `~/.nix-profile/bin/vim` is a
wrapper script that invokes vim with `-u <store-path-vimrc>`. This means
`~/.vimrc` simply doesn't exist after this slice — editing it has no effect.
To change vim config, edit `nix/profiles/all/vim.nix` and run `./apply`.

**One-time apply notes:**

- On first apply, the activation moves your existing `~/.vimrc` to
  `~/.vimrc.legacy-backup`, `~/.vim/autoload/` (containing the old
  `pathogen.vim`) to `~/.vim/autoload.legacy-backup/`, and `~/.vim/bundle/`
  (the three git-cloned plugins) to `~/.vim/bundle.legacy-backup/`. Once
  you've confirmed vim still works the way you want, you can delete the
  `.legacy-backup` paths at your leisure.

- `~/.vim/{backups,swaps,undo}/` are NOT touched by the migration. They
  contain real vim state (backup copies of files you've edited, swap files
  for recovery, undo history). The slice creates these directories
  declaratively via `home.file` `.keep` placeholders so a fresh machine
  has them, but never manages their contents.

- If you had local edits to `~/.vimrc` or any of the bundle plugins, look
  for them in the `.legacy-backup` paths and reapply manually if needed —
  the slice's `programs.vim.extraConfig` matches the legacy `.vimrc` body
  minus the `pathogen#infect()` line.

**Private flake update (only if you have one):**

If your private flake adds `programs.vim.plugins` or `programs.vim.extraConfig`
entries, Nix module merging handles them additively on top of the public
baseline. Conflicting keys (e.g., overriding the colorscheme) need
`lib.mkForce` in the private module.

For the nix-claude slice (`claude` plugin retired; `~/.claude/` config now home-manager managed):

This slice migrates the bash `claude` plugin (which "built" `~/.claude/CLAUDE.md`
from a renamed source then rsynced it) into home-manager. The personal Claude
Code config — `CLAUDE.md`, `settings.json`, and `guides/` — is now managed
declaratively in the `default` profile. `settings.json` is generated from a Nix
attrset (`pkgs.formats.json`); `CLAUDE.md` and the guides are sourced from
`nix/profiles/default/claude/`.

**Individual files, not directories.** `~/.claude/` holds a lot of live Claude
Code state (projects, plugins, sessions, history, auto-memory). The slice
manages only the specific files it owns and never symlinks a whole directory,
so your state and any ad-hoc content (e.g. a hand-written `~/.claude/commands/`
entry) are left untouched.

**Adding agents, skills, commands, or rules.** Drop a file under the matching
directory in the repo and run `./apply`:

- `nix/profiles/default/claude/agents/<name>.md` → `~/.claude/agents/<name>.md`
- `nix/profiles/default/claude/skills/<name>/SKILL.md` → `~/.claude/skills/<name>/SKILL.md`
- `nix/profiles/default/claude/commands/<name>.md` → `~/.claude/commands/<name>.md`
- `nix/profiles/default/claude/rules/<name>.md` → `~/.claude/rules/<name>.md`

The Nix module auto-discovers every file under those directories. The target
dirs stay writable, so Claude-Code-authored files alongside your managed ones
coexist.

**One-time apply notes:**

- On first apply, the activation moves your existing rsynced `~/.claude/CLAUDE.md`,
  `~/.claude/settings.json`, and `~/.claude/guides/*.md` to `*.legacy-backup`
  siblings, then home-manager links the Nix-managed versions. Delete the
  `.legacy-backup` files once you've confirmed everything's in order.

- `settings.json` is now generated from `nix/profiles/default/claude.nix`. To
  change a setting, edit the Nix attrset and run `./apply` — editing
  `~/.claude/settings.json` directly has no lasting effect (it's a symlink into
  the Nix store).

**Private flake update (only if you have one):**

If your private flake adds `home.file.".claude/..."` entries or overrides
settings keys, Nix module merging handles additive entries; conflicting keys
need `lib.mkForce`.

For the nix-vscode slice (`vscode` plugin retired; `code` CLI now provided by the cask):

The bash `vscode` plugin only symlinked VS Code's `code` CLI helper onto PATH.
That's now redundant: the `visual-studio-code` cask (declared in nix-darwin since
the nix-darwin slice) lists `code` and `code-tunnel` as binary artifacts, so
Homebrew links them into `/opt/homebrew/bin/` (on PATH) when it installs the
cask. The plugin is deleted with no replacement — Homebrew owns the symlink.

**One-time apply notes:**

- No action needed. If `code` ever goes missing after a VS Code reinstall, run
  `brew reinstall --cask visual-studio-code` to relink the binary artifacts, or
  use VS Code's "Shell Command: Install 'code' command in PATH" from the command
  palette.

For the nix-homedir slice (`environments/all/home/` rsync content → home-manager; the homedir plugin stays for custom_environments):

This slice migrates the universal rsync dotfiles into home-manager: the global
gitignore (`programs.git.ignores`), `.screenrc` (`programs.screen`), `.gemrc` /
`.wgetrc` / `.hushlogin` (`home.file`), the `~/bin/git-*` helper scripts
(`home.file`, executable, per-file so `~/bin` stays writable), and `~/.ssh/config`
(`home.file` with the macOS-only `UseKeychain` gated by platform).

The `homedir` bash plugin is NOT retired — it still rsyncs
`custom_environments/<env>/home/`. It retires in a later slice once
custom_environments is migrated.

**One-time apply notes:**

- On first apply, an activation deletes the now-vestigial rsynced copies of
  these files from `$HOME` (`.gemrc`, `.wgetrc`, `.screenrc`, `.hushlogin`,
  `.gitignore`, `.ssh/config`, and the `~/bin/git-*` scripts) so home-manager
  can link the managed versions. No backup is kept — they were exact copies of
  tracked repo content. Your non-managed `~/bin` entries, `~/.ssh` keys, and
  `known_hosts` are untouched.

- The global gitignore moved from `~/.gitignore` to `~/.config/git/ignore`
  (git reads `~/.config/git/ignore` natively as its XDG default — no
  `core.excludesFile` needed, which is why this slice drops it). A pre-existing
  `~/.config/git/ignore` pattern (`**/.claude/settings.local.json`) was folded
  into `programs.git.ignores`, so it's preserved.

**Private flake update (only if you have one):**

If your private flake adds `home.file` entries or `programs.git.ignores`, Nix
module merging handles additive entries; conflicting keys need `lib.mkForce`.

For the nix-terminal-fonts slice (iTerm2 + Terminal.app Nerd Font, declarative):

Closes the terminal-font deferral. The nix-firstrun attempt wrote a top-level
`Normal Font` pref (ignored — the font lives per-profile) with a typo'd
PostScript name. This slice patches the font onto your EXISTING profiles in
place via a Python plistlib `defaults export → modify → import` round-trip
(`nix/profiles/default/patch-terminal-fonts.py`, run from a home-manager
activation):

- **iTerm2** — the `Default` and `tmux` profiles get `Normal Font` /
  `Non Ascii Font` set to `MesloLGSNF-Regular 14` ("MesloLGS Nerd Font").
- **Terminal.app** — the `Homebrew` profile's `Font` (a binary NSFont blob,
  generated once via Swift and stored with a regen comment) is set.

**CONSTRAINT: quit iTerm2 and Terminal.app before `./apply`.** Both rewrite
their prefs on quit, so a running app reverts the change. Relaunch them after
applying to see the font. The patch is idempotent.

**Changing the font:** edit `font` in `nix/profiles/default/terminal-fonts.nix`.
For Terminal.app, also regenerate the NSFont blob (the Swift one-liner is in the
file's comment). The font itself is installed by the `font-meslo-lg-nerd-font`
cask (nix-darwin slice), not here.

For the framework-collapse slice (the homegrown plugin framework retired; `./apply` now runs on stock Bash 3.2.57):

Closes the last public-side deferral — the bash-bootstrap chicken-and-egg.
Instead of bootstrapping a modern Bash before Nix, the plugin framework (which
was the only thing needing Bash 4+) is collapsed: `./apply` is now a flat,
Bash-3.2-safe script and the nix logic moved to `lib/nix`.
`framework/{framework,plugin,util,customize}` and the `plugins/` tree are
deleted. The per-environment `home/` rsync (the old `homedir` plugin) is also
gone — public `home/` content already migrated to home-manager, and any
`custom_environments/<env>/home/` content should now be managed by that env's
private flake (`custom_environments/<env>/nix`).

- **No private-flake change needed for the public profiles.** This slice
  restructures the public bootstrap. **If your private env relied on the
  `home/` rsync** (e.g. a `custom_environments/work/home/` overlay), move those
  files into your private flake's `nix/files/home/` tree — `./apply` no longer
  rsyncs them.
- **First `./apply` after this slice:** nix-darwin's `cleanup = "uninstall"`
  removes the now-undeclared `bash` and `bash-completion@2` Homebrew formulas.
  General-purpose Bash 5 is provided by the nixpkgs `bash` in `home.packages`
  (`~/.nix-profile/bin/bash`); bash completion is wired by home-manager's
  `programs.bash.enableCompletion` (default), sourcing the nixpkgs
  `bash-completion`. Open a fresh shell afterward and confirm `bash --version`
  is 5.x and tab-completion still works.
- **`custom_environments` is now cloned/updated manually** — the `customize`
  helper that auto-cloned it was removed. `git clone` your private repo into
  `custom_environments/` once; `./apply` discovers it from there as before.

The same shape applies to future slices that migrate a plugin or rsync
source: add the new options to your private flake, delete the now-orphaned
rsync source from your private repo, and trust the activation cleanup.

## Backout

- **Disable the slice:** set `DOTFILES_NIX_SKIP=1` before `./apply`.
- **Drop a managed file:** remove its lines from `home.nix` and re-activate;
  home-manager removes only symlinks it created.
- **Remove Nix entirely:** delete `lib/nix` and `nix/`, then uninstall Nix:
  - **macOS** (Determinate): `/nix/nix-installer uninstall`.
  - **Linux** (official single-user): `nix-env --uninstall nix`, then
    `rm -rf ~/.nix-profile ~/.nix-defexpr ~/.nix-channels /nix` and remove the
    nix lines from your shell rc.
- **Remove nix-darwin entirely:** more involved than home-manager rollback.
  - `sudo darwin-rebuild --rollback` reverts to the previous nix-darwin generation but doesn't uninstall.
  - To fully uninstall: `sudo /nix/var/nix/profiles/system/sw/bin/darwin-uninstaller`. This removes `/etc/static/` symlinks and the system profile; it does NOT touch your installed casks/mas (manage those via brew directly).
  - `git revert` of this slice's commits restores the bash plugins (homebrew/homebrew_core/xcode) but does NOT revert nix-darwin's system-state changes. Manual `/etc/passwd`/`/etc/shells` cleanup may be needed (look for `/etc/shells.before-nix-darwin` — that's nix-darwin's pre-takeover backup).

## License

Same as the parent dotfiles repository.
