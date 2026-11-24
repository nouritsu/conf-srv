let
  port = 3923;
in {
  # copyparty over valheim's admin lists, plugins and worlds; needs games.valheim and caddy
  den.aspects.games.valheim-files = {
    endpoint = {
      subdomain = "valheim-files";
      public = true;
      inherit port;
    };

    nixos = {config, ...}: let
      owner = {
        owner = config.users.users.valheim.name;
        group = config.users.users.valheim.group;
      };
    in {
      sops.secrets."copyparty/admin-password" = owner;
      sops.secrets."copyparty/mod-password" = owner;

      sops.templates."valheim-files.conf" =
        owner
        // {
          content = ''
            [global]
            p: 3923
            hist: /cfg/hists/
            e2dsa
            e2ts
            rproxy: 1
            xff-src: lan
            usernames

            [accounts]
            admin: ${config.sops.placeholder."copyparty/admin-password"}
            mod: ${config.sops.placeholder."copyparty/mod-password"}

            [/admin]
            /admin
              accs:
                rwma.: admin

            [/plugin]
            /plugin
              accs:
                A: admin
                rwdm.: mod

            [/world]
            /world
              accs:
                A: admin
                rwdm.: mod
          '';
        };

      virtualisation.oci-containers.containers.valheim-files = {
        image = "copyparty/ac:latest@sha256:75c58da287339fc4fd93974b4f19b72a2e7efe5431edf405b4b3295f0662a711";

        ports = ["${toString port}:3923"];

        volumes = [
          "/data/copyparty:/cfg"
          "${config.sops.templates."valheim-files.conf".path}:/cfg/copyparty.conf:ro"

          # admin
          "/data/valheim/config/adminlist.txt:/admin/adminlist.txt"
          "/data/valheim/config/bannedlist.txt:/admin/bannedlist.txt"
          "/data/valheim/config/permittedlist.txt:/admin/permittedlist.txt"

          # plugin
          "/data/valheim/config/bepinex/plugins:/plugin/plugins"
          "/data/valheim/config/bepinex:/plugin/config"

          # world
          "/data/valheim/config/worlds_local:/world"
        ];

        extraOptions = ["--user=${toString config.users.users.valheim.uid}:${toString config.users.groups.valheim.gid}"];
      };

      systemd.tmpfiles.rules = [
        "d /data/copyparty 0755 valheim valheim -"
        "d /data/copyparty/hists 0755 valheim valheim -"
        "d /data/valheim/config/worlds_local 0755 valheim valheim -"
      ];
    };
  };
}
