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
  # Every agent host gets the same content — cluster tooling, tmux, the Claude
  # config and its managed-settings policy. What differs per host is the host's
  # own business and lives with whatever runs it: the homelab pods clone their
  # repos, set the git identity, and write the github.com bot-key ssh block from
  # `images/dev-base/lib/bootstrap.sh`, not from this bundle.
  imports = [
    ../claude
    ./cli-tools.nix
    ./claude.nix
    ./shell-extras.nix
  ];
}
