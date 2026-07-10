{ ... }: {
  # Shared-optional bundle: the tooling and machinery needed to run Claude (and
  # other agents) unattended over SSH. An environment opts in by adding
  # `public.homeModules.agent` to the `modules` list it passes to `mkHome`.
  #
  # The bundle imports `../claude` so a consuming environment gets the shared
  # ~/.claude content (rules, agents, base CLAUDE.md, the settings.json
  # seed/merge) without listing that bundle separately. The module system
  # dedupes, so an environment may still list `public.homeModules.claude`.
  #
  # Every agent host gets the same content — cluster tooling, credential
  # restore, project cloning, tmux, the managed-settings policy. The one
  # per-host difference is which repos to clone, set through
  # `dotfiles.agent.reposFile` (see ./projects.nix).
  imports = [
    ../claude
    ./cli-tools.nix
    ./claude.nix
    ./projects.nix
    ./shell-extras.nix
  ];
}
