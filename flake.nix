{
  description = "My servers: the rpi5 homelab, the vps in front of it, and a game server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    # upstream nix-minecraft has no forge servers
    nix-minecraft = {
      url = "github:hustlerone/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    den.url = "github:denful/den";

    # nixos-raspberrypi pins the nixpkgs that actually builds the system; disko
    # only exposes plain NixOS modules, which take pkgs from the host, so its
    # own nixpkgs was dead weight in the lock.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # its own nixpkgs is what cache.thalheim.io built sops-install-secrets against
    sops-nix.url = "github:Mic92/sops-nix";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # shell tools carry their config, as on pc; wrapped with the host's pkgs
    wrappers = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # the pc's config, for starship's settings and theme
    conf-nixos = {
      url = "git+https://codeberg.org/nouritsu/nixos";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        import-tree.follows = "import-tree";
        den.follows = "den";
        treefmt-nix.follows = "treefmt-nix";
        wrappers.follows = "wrappers";
      };
    };

    # Theming
    nix-colors.url = "github:misterio77/nix-colors";
    # parsed at eval time; no catppuccin/nix for two theme files
    catppuccin-btop = {
      url = "github:catppuccin/btop";
      flake = false;
    };
    catppuccin-television = {
      url = "github:catppuccin/television";
      flake = false;
    };
  };

  outputs = inputs @ {
    flake-parts,
    import-tree,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # `systems` is set by den, from `den.systems` in modules/flake/den.nix
      imports = [
        (import-tree ./modules)
        ./shell.nix
      ];
    };
}
