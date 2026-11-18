{den, ...}: let
  state-dir = "/var/lib/cn-calsync";
in {
  # campusnet's schedule as ics feeds, one per event type, for proton calendar to subscribe to
  den.aspects.edge.cn-calsync = {
    endpoint = {
      subdomain = "cal";
      public = true;
      # the secret token is a directory name, so it never appears here
      extraConfig = ''
        root * ${state-dir}/feeds
        @ics path *.ics
        header @ics Content-Type "text/calendar; charset=utf-8"
        file_server
      '';
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cn-calsync = pkgs.writers.writePython3Bin "cn-calsync" {
        libraries = with pkgs.python3Packages; [beautifulsoup4 icalendar requests];
        flakeIgnore = ["E501"];
      } (builtins.readFile ./cn-calsync.py);

      secrets = {
        username = "campusnet/username";
        password = "campusnet/password";
        feed-token = "cn-calsync/feed-token";
      };
    in {
      sops.secrets =
        lib.mapAttrs' (_: s: lib.nameValuePair s {}) secrets
        # the homelab's Home Assistant reads the feeds with it too
        // {${secrets.feed-token}.sopsFile = den.lib.homelab.shared-secrets;};

      # static rather than DynamicUser: caddy can't reach /var/lib/private
      users.users.cn-calsync = {
        isSystemUser = true;
        group = "cn-calsync";
      };
      users.groups.cn-calsync = {};

      systemd.services.cn-calsync = {
        description = "Sync the CampusNet schedule into ics feeds";
        wants = ["network-online.target"];
        after = ["network-online.target"];

        # campusnet times out often; a few retries, then wait for the next slot
        startLimitIntervalSec = 2 * 60 * 60;
        startLimitBurst = 4;

        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe cn-calsync;
          User = "cn-calsync";
          Group = "cn-calsync";

          LoadCredential = lib.mapAttrsToList (name: s: "${name}:${config.sops.secrets.${s}.path}") secrets;

          # 0711: caddy can open the token's path, nobody can list it
          StateDirectory = "cn-calsync";
          StateDirectoryMode = "0711";
          LogsDirectory = "cn-calsync";
          LogsDirectoryMode = "0700";

          Restart = "on-failure";
          RestartSec = "15min";

          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        };
      };

      systemd.timers.cn-calsync = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "*-*-* 00,06,16:00:00";
          Persistent = true;
        };
      };
    };
  };
}
