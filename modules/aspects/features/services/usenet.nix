{den, ...}: let
  port = 8083;
in {
  den.aspects.services.sabnzbd = {
    endpoint = {
      subdomain = "usenet";
      inherit port;
    };
    gluetun-ports = ["${toString port}:8080"];

    nixos = {
      imports = [(den.lib.homelab.via-gluetun "sabnzbd")];

      virtualisation.oci-containers.containers.sabnzbd = {
        image = "lscr.io/linuxserver/sabnzbd:latest@sha256:b356d0a9b22db584e9005364ec4e752dfc081ce501b7145e9a5c0bb38e4d1ba4";

        environment = {
          DOCKER_MODS = "ghcr.io/themepark-dev/theme.park:sabnzbd";
          TP_THEME = "catppuccin-mocha";
          TP_COMMUNITY_THEME = "true";
        };

        volumes = ["/data/sabnzbd:/config" "/media/download:/data"];
      };

      systemd.tmpfiles.rules = [
        "d /data/sabnzbd 0775 1000 data -"
        "d /media/download/usenet 2775 1000 data -"
        "d /media/download/usenet/nzbs 2775 1000 data -"
        "d /media/download/usenet/incomplete 2775 1000 data -"
        "d /media/download/usenet/complete 2775 1000 data -"
      ];

      systemd.services.podman-sabnzbd.preStart = ''
        mkdir -p /data/sabnzbd

        config_file="/data/sabnzbd/sabnzbd.ini"
        whitelist_hosts="${den.lib.homelab.fqdn "usenet"}, localhost, 127.0.0.1"

        if [ -f "$config_file" ]; then
          if grep -q "^host_whitelist" "$config_file"; then
            sed -i "s|^host_whitelist.*|host_whitelist = $whitelist_hosts|" "$config_file"
          else
            if grep -q "^\[misc\]" "$config_file"; then
              sed -i "/^\[misc\]/a host_whitelist = $whitelist_hosts" "$config_file"
            fi
          fi
        fi
      '';
    };
  };
}
