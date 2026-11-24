{den, ...}: {
  den.aspects.edge.www = {
    endpoint = {
      domain = den.lib.homelab.base-domain;
      public = true;
      extraConfig = ''
        root * /srv/www/public_html
        file_server
      '';
    };

    nixos = {
      # nouritsu/nouritsu's codeberg ci (nix run .#deploy) rsyncs the built site in as this user
      users.users.website-deployer = {
        isNormalUser = true;
        description = "Codeberg CI Website Deployer";
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjDhZkazCNhJj2szvv3SLUd7a6sJrevLFbOOvhSoHYL nouritsu-website-deploy"
        ];
      };

      systemd.tmpfiles.rules = [
        "d /srv/www/public_html 0775 website-deployer caddy - -"
      ];
    };
  };
}
