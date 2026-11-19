{den, ...}: let
  inherit (den.lib.homelab) base-domain fqdn;

  port = 8080;
  stun-port = 3478;
in {
  # the control server the homelab's tailscale logs in to
  den.aspects.edge.headscale = {
    endpoint = {
      subdomain = "vpn";
      public = true;
      inherit port;
    };

    nixos = {config, ...}: {
      sops.secrets."headscale/oicd-client-id" = {};
      sops.secrets."headscale/oicd-client-secret" = {};
      # space-separated emails; without them any google account may register a node
      sops.secrets."headscale/allowed-users" = {};

      sops.templates."headscale-oidc.env" = {
        content = ''
          HEADSCALE_OIDC_CLIENT_ID="${config.sops.placeholder."headscale/oicd-client-id"}"
          HEADSCALE_OIDC_CLIENT_SECRET="${config.sops.placeholder."headscale/oicd-client-secret"}"
          HEADSCALE_OIDC_ALLOWED_USERS="${config.sops.placeholder."headscale/allowed-users"}"
        '';
        restartUnits = ["headscale.service"];
      };

      services.headscale = {
        enable = true;
        address = "0.0.0.0";
        inherit port;
        settings = {
          server_url = "https://${fqdn "vpn"}";

          derp.server = {
            enabled = true;
            stun_listen_addr = "0.0.0.0:${toString stun-port}";
          };

          dns = {
            base_domain = "tail.${base-domain}";
            override_local_dns = true;
            nameservers.global = ["100.64.0.1"];
          };

          oidc = {
            only_start_if_oidc_is_available = true;
            issuer = "https://accounts.google.com";

            scope = [
              "openid"
              "profile"
              "email"
            ];
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d /data/headscale 0750 headscale headscale -"
      ];

      systemd.services.headscale.serviceConfig = {
        BindPaths = [
          "/data/headscale:/var/lib/headscale"
        ];

        EnvironmentFile = [
          config.sops.templates."headscale-oidc.env".path
        ];
      };

      environment.systemPackages = [config.services.headscale.package];
      networking.firewall.allowedUDPPorts = [stun-port];
    };
  };
}
