{den, ...}: let
  # off 3000: rathole binds the homelab's documenso there
  port = 3030;
in {
  # headscale's web ui; reads headscale's own settings, so it lives beside it
  den.aspects.edge.headplane = {
    endpoint = {
      subdomain = "mesh";
      public = true;
      inherit port;
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      fmt = pkgs.formats.yaml {};
      headscale-config = fmt.generate "headscale.yml" (lib.recursiveUpdate config.services.headscale.settings {
        tls_cert_path = "/dev/null";
        tls_key_path = "/dev/null";
        policy.path = "/dev/null";
      });
    in {
      sops.secrets."headplane/cookie-secret".owner = "headscale";
      # from `headscale apikeys create`; oidc sessions reach headscale through it
      sops.secrets."headplane/api-key".owner = "headscale";

      # headscale's own google client, with mesh's callback among its redirect uris
      sops.templates."headplane.env" = {
        content = ''
          HEADPLANE_OIDC__CLIENT_ID="${config.sops.placeholder."headscale/oicd-client-id"}"
          HEADPLANE_OIDC__CLIENT_SECRET="${config.sops.placeholder."headscale/oicd-client-secret"}"
        '';
        restartUnits = ["headplane.service"];
      };

      # no agent: since 0.7 it needs a headscale api key, not a pre-auth key
      services.headplane = {
        enable = true;
        settings = {
          server = {
            host = "127.0.0.1";
            inherit port;
            base_url = "https://${den.lib.homelab.fqdn "mesh"}";
            cookie_secret_path = config.sops.secrets."headplane/cookie-secret".path;
          };
          headscale = {
            url = "http://127.0.0.1:${toString config.services.headscale.port}";
            config_path = "${headscale-config}";
            api_key_path = config.sops.secrets."headplane/api-key".path;
          };
          # the first login becomes owner, later ones members without access
          oidc = {
            issuer = "https://accounts.google.com";
            # overridden from headplane.env
            client_id = "";
          };
        };
      };

      systemd.services.headplane.serviceConfig.EnvironmentFile = config.sops.templates."headplane.env".path;
    };
  };
}
