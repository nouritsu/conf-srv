{den, ...}: let
  port = 8085;
in {
  den.aspects.services.radarr = {
    endpoint = {
      subdomain = "movies";
      inherit port;
    };
    gluetun-ports = ["${toString port}:7878"];

    nixos = {
      imports = [(den.lib.homelab.via-gluetun "radarr")];

      virtualisation.oci-containers.containers.radarr = {
        image = "lscr.io/linuxserver/radarr:latest@sha256:044788f5508b7f67a3e0368cdd142c77c4d4cd5aec2efaba53e1a68b6b6231e7";
        volumes = ["/data/radarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/radarr 0775 1000 data -"
        "d /media/media/movies 2775 1000 data -"
      ];
    };
  };
}
