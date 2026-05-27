{ ... }: {
  # `all` is composed into every config by `lib.mkHome`, regardless of which
  # profile is active or whether a private flake overlays on top — anything
  # *every* machine should get goes here. Split into per-feature submodules
  # so each feature stays focused and reviewable.
  imports = [
    ./cli-tools.nix
    ./dotfilesrc-cleanup.nix
    ./git.nix
    ./gpg.nix
    ./shells.nix
  ];
}
