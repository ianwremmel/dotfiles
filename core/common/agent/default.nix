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
  # Anything specific to one agent host — a cluster's CLIs, its MCP servers,
  # which repos to clone — belongs in the consuming environment, not here.
  imports = [
    ../claude
    ./cli-tools.nix
    ./claude.nix
  ];
}
