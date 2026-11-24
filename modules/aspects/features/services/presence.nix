let
  port = 8092;
  state-dir = "/var/lib/presence";
  # services.beszel's hub, on this host
  hub = "http://127.0.0.1:8090";
in {
  # whether I am about, for the website's frame: online while the pc is up, away while
  # only the laptop is, offline while neither. Read from beszel every five minutes; only
  # that word is published, and only once it has held for ten.
  den.aspects.services.presence = {
    # only a tunnel: edge.presence proxies nouritsu.com/status.json to it
    endpoint = {
      subdomain = "presence";
      inherit port;
      public = true;
      vhost = false;
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      presence = pkgs.writers.writePython3Bin "presence" {
        flakeIgnore = ["E501"];
      } (builtins.readFile ./presence.py);
    in {
      # a beszel user of its own: role readonly, and the pc and the laptop the only
      # systems shared with it, so even its password shows nothing else
      sops.secrets."presence/email" = {};
      sops.secrets."presence/password" = {};

      # static rather than DynamicUser: caddy can't reach /var/lib/private
      users.users.presence = {
        isSystemUser = true;
        group = "presence";
      };
      users.groups.presence = {};

      systemd.services.presence = {
        description = "Publish whether I am about, from the beszel hub";
        after = ["beszel-hub.service"];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.escapeShellArgs [
            (lib.getExe presence)
            "--hub"
            hub
            "--online"
            "pc"
            "--away"
            "laptop"
            "--hold"
            "600"
            "--state"
            "${state-dir}/state.json"
            "--out"
            "${state-dir}/public/status.json"
          ];
          User = "presence";
          Group = "presence";
          LoadCredential = [
            "email:${config.sops.secrets."presence/email".path}"
            "password:${config.sops.secrets."presence/password".path}"
          ];

          # 0711: caddy can open public/status.json by its path, nobody can list either
          StateDirectory = ["presence" "presence/public"];
          StateDirectoryMode = "0711";

          # it talks to the hub on this host and nothing else
          IPAddressAllow = "localhost";
          IPAddressDeny = "any";
          RestrictAddressFamilies = ["AF_INET" "AF_INET6"];

          CapabilityBoundingSet = "";
          LockPersonality = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictNamespaces = true;
          SystemCallArchitectures = "native";
        };
      };

      systemd.timers.presence = {
        wantedBy = ["timers.target"];
        timerConfig.OnCalendar = "*:0/5";
      };

      # the tunnel's end: the one file, and nothing else, not even a listing
      services.caddy.virtualHosts."http://:${toString port}" = {
        listenAddresses = ["127.0.0.1"];
        extraConfig = ''
          handle /status.json {
            root * ${state-dir}/public
            header Cache-Control "no-cache"
            file_server
          }
          handle {
            respond 404
          }
        '';
      };
    };
  };
}
