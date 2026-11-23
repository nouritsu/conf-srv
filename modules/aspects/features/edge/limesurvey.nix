{den, ...}: let
  port = 3040;
in {
  den.aspects.edge.limesurvey = {
    endpoint = {
      subdomain = "forms";
      public = true;
      inherit port;
    };

    nixos = {config, ...}: {
      sops.secrets."forms/encryption-key" = {};
      sops.secrets."forms/encryption-nonce" = {};

      services.limesurvey = {
        enable = true;
        webserver = "nginx";
        nginx.virtualHost = {
          serverName = den.lib.homelab.fqdn "forms";
          listen = [
            {
              addr = "127.0.0.1";
              inherit port;
            }
          ];
        };
        encryptionKeyFile = config.sops.secrets."forms/encryption-key".path;
        encryptionNonceFile = config.sops.secrets."forms/encryption-nonce".path;
      };
    };
  };
}
