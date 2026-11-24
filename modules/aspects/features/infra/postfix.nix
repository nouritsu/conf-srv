{den, ...}: {
  den.aspects.postfix.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (den.lib.homelab) base-domain smtp;
    relay = "[${smtp.host}]:${toString smtp.port}";
    address = config.sops.placeholder."mail/address";

    # restic retries hourly while the pc is off, so its failures aren't news
    watched = lib.filterAttrs (n: _: !lib.hasPrefix "restic-backups-" n) config.systemd.timers;
    notify-dropin = pkgs.writeText "notify-failure.conf" ''
      [Unit]
      OnFailure=notify-failure@%n.service
    '';
  in {
    sops.secrets."mail/address" = {};
    sops.secrets."mail/token" = {};
    sops.secrets."mail/admin".sopsFile = den.lib.homelab.shared-secrets;
    sops.templates."mail-sasl-password" = {
      content = "${relay} ${address}:${config.sops.placeholder."mail/token"}";
    };
    # proton only relays mail sent as the address the token belongs to
    sops.templates."mail-sender" = {
      content = "/.+/ ${address}";
    };
    sops.templates."mail-recipient" = {
      content = "/^(root|postmaster)@/ ${config.sops.placeholder."mail/admin"}";
    };

    services.postfix = {
      enable = true;
      settings.main = {
        mydomain = base-domain;
        myorigin = base-domain;
        mydestination = [];
        mynetworks = ["127.0.0.0/8" "[::1]/128"];
        relayhost = [relay];
        sender_canonical_maps = "regexp:${config.sops.templates."mail-sender".path}";
        recipient_canonical_maps = "regexp:${config.sops.templates."mail-recipient".path}";
        smtp_tls_security_level = "secure";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_password_maps = "texthash:${config.sops.templates."mail-sasl-password".path}";
        smtp_sasl_security_options = "noanonymous";
        inet_interfaces = "loopback-only";
      };
    };

    # every timer's job mails root when it fails
    systemd.services."notify-failure@" = {
      description = "Mail root that %i failed";
      serviceConfig.Type = "oneshot";
      scriptArgs = "%i";
      path = [config.systemd.package];
      script = ''
        {
          printf 'To: root\nSubject: %s: %s failed\n\n' ${config.networking.hostName} "$1"
          systemctl status --full --no-pager --lines=40 "$1" || true
        } | ${config.security.wrapperDir}/sendmail -t
      '';
    };
    systemd.packages = [
      (pkgs.linkFarm "notify-failure-dropins" (lib.mapAttrsToList (n: t: {
          name = "lib/systemd/system/${t.timerConfig.Unit or "${n}.service"}.d/notify-failure.conf";
          path = notify-dropin;
        })
        watched))
    ];

    environment.systemPackages = [pkgs.mailutils];
  };
}
