{den, ...}: let
  inherit (den.lib.homelab) smtp;
  domain = den.lib.homelab.fqdn "forms";
  port = 3040;
in {
  den.aspects.edge.heyform = {
    endpoint = {
      subdomain = "forms";
      public = true;
      inherit port;
    };

    nixos = {
      config,
      pkgs,
      ...
    }: {
      imports = [(den.lib.homelab.private-network "heyform" ["heyform" "heyform-mongo" "heyform-redis"])];

      sops.secrets."forms/session-key" = {};
      sops.secrets."forms/form-encryption-key" = {};
      sops.secrets."mail/address" = {};
      sops.secrets."mail/token" = {};
      sops.templates."heyform.env".content = ''
        SESSION_KEY=${config.sops.placeholder."forms/session-key"}
        FORM_ENCRYPTION_KEY=${config.sops.placeholder."forms/form-encryption-key"}
        SMTP_USER=${config.sops.placeholder."mail/address"}
        SMTP_PASSWORD=${config.sops.placeholder."mail/token"}
        SMTP_FROM=HeyForm <${config.sops.placeholder."mail/address"}>
      '';

      virtualisation.oci-containers.containers = {
        heyform = {
          image = "docker.io/heyform/community-edition:v3.0.8@sha256:695ad2a1dbe756a2592c674a61c9b06cecedee8b04bf0b9c9f7594aaca22818f";
          dependsOn = ["heyform-mongo" "heyform-redis"];
          ports = ["127.0.0.1:${toString port}:9157"];
          environment = {
            APP_HOMEPAGE_URL = "https://${domain}";
            TRUST_PROXY = "1";
            APP_DISABLE_REGISTRATION = "true";
            ENABLE_GOOGLE_FONTS = "false";
            SMTP_HOST = smtp.host;
            SMTP_PORT = toString smtp.port;
            # starttls on 587, not implicit tls
            SMTP_SECURE = "false";
            MONGO_URI = "mongodb://heyform-mongo:27017/heyform";
            REDIS_HOST = "heyform-redis";
          };
          environmentFiles = [config.sops.templates."heyform.env".path];
          volumes = ["heyform-uploads:/app/packages/server/static/upload"];
        };

        heyform-mongo = {
          image = "docker.io/library/mongo:8@sha256:747773029b84309981a3624a1af64ffc8c4d792283cc0834f26fe01fc6d28b34";
          volumes = ["heyform-mongo:/data/db"];
        };

        heyform-redis.image = "docker.io/valkey/valkey:9@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd";
      };

      systemd.timers.restart-container-heyform-mongo.enable = false; # database

      # maple mono for the forms' custom css
      services.caddy.virtualHosts.${domain}.extraConfig = ''
        handle_path /fonts/* {
          root * ${pkgs.maple-mono.woff2}/share/fonts/woff2
          file_server
        }
      '';
    };
  };
}
