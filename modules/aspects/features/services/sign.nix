{den, ...}: let
  inherit (den.lib.homelab) smtp;

  domain = den.lib.homelab.fqdn "sign";
  port = 3000;
in {
  den.aspects.services.documenso = {
    endpoint = {
      subdomain = "sign";
      public = true;
      inherit port;
    };
    backup.paths = ["/var/lib/containers/storage/volumes/documenso-db"];

    nixos = {config, ...}: {
      imports = [(den.lib.homelab.private-network "documenso" ["documenso" "documenso-db"])];

      sops.secrets."documenso-cert" = {
        sopsFile = ../secrets/cert.p12.enc;
        format = "binary";
        mode = "0644";
      };
      sops.secrets."sign/nextauth-secret" = {};
      sops.secrets."sign/next-key" = {};
      sops.secrets."sign/next-secondary-key" = {};
      sops.secrets."sign/next-signing-pass" = {};
      sops.secrets."mail/home-password" = {};
      sops.secrets."mail/home-mail" = {};
      sops.secrets."sign/sign-mail" = {};
      sops.secrets."sign/postgres-password" = {};

      sops.templates."documenso.env" = {
        content = ''
          NEXTAUTH_SECRET=${config.sops.placeholder."sign/nextauth-secret"}
          NEXT_PRIVATE_ENCRYPTION_KEY=${config.sops.placeholder."sign/next-key"}
          NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY=${config.sops.placeholder."sign/next-secondary-key"}
          NEXT_PRIVATE_SIGNING_PASSPHRASE=${config.sops.placeholder."sign/next-signing-pass"}
          NEXT_PRIVATE_SMTP_USERNAME=${config.sops.placeholder."mail/home-mail"}
          NEXT_PRIVATE_SMTP_FROM_ADDRESS=${config.sops.placeholder."sign/sign-mail"}
          NEXT_PRIVATE_SMTP_PASSWORD=${config.sops.placeholder."mail/home-password"}
          NEXT_PRIVATE_DATABASE_URL=postgresql://documenso:${config.sops.placeholder."sign/postgres-password"}@documenso-db:5432/documenso
          NEXT_PRIVATE_DIRECT_DATABASE_URL=postgresql://documenso:${config.sops.placeholder."sign/postgres-password"}@documenso-db:5432/documenso
        '';
      };

      sops.templates."documenso-postgres.env" = {
        content = ''
          POSTGRES_PASSWORD=${config.sops.placeholder."sign/postgres-password"}
        '';
      };

      virtualisation.oci-containers.containers.documenso = {
        image = "documenso/documenso:latest@sha256:d9985f66c19c59128f64b1439f057683da0110deb0e518655b97f06e3141f173";
        dependsOn = ["documenso-db"];
        ports = ["127.0.0.1:${toString port}:3000"];
        environment = {
          NEXT_PRIVATE_SMTP_HOST = smtp.host;
          NEXT_PRIVATE_SMTP_PORT = toString smtp.port;
          NEXT_PRIVATE_SMTP_SECURE = "true";
          PORT = toString port;
          NEXTAUTH_URL = "https://${domain}";
          NEXT_PUBLIC_WEBAPP_URL = "https://${domain}";
          NEXT_PRIVATE_INTERNAL_WEBAPP_URL = "http://localhost:${toString port}";
          NEXT_PRIVATE_SMTP_TRANSPORT = "smtp-auth";
          NEXT_PRIVATE_SMTP_FROM_NAME = "Documenso";
          NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH = "/opt/documenso/cert.p12";
          NEXT_PUBLIC_DISABLE_SIGNUP = "true";
          DOCUMENSO_DISABLE_TELEMETRY = "true";
        };
        environmentFiles = [config.sops.templates."documenso.env".path];
        volumes = ["${config.sops.secrets."documenso-cert".path}:/opt/documenso/cert.p12:ro"];
      };

      virtualisation.oci-containers.containers.documenso-db = {
        image = "postgres:15@sha256:5a407822929c3789ff5154d3d35bd7e2090318149344c8a3d4ca942b035822ed";
        environment = {
          POSTGRES_USER = "documenso";
          POSTGRES_DB = "documenso";
        };
        environmentFiles = [config.sops.templates."documenso-postgres.env".path];
        volumes = ["documenso-db:/var/lib/postgresql/data"];
        extraOptions = [
          "--health-cmd=pg_isready -U documenso"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=5"
        ];
      };

      systemd.timers.restart-container-documenso-db.enable = false; # database
    };
  };
}
