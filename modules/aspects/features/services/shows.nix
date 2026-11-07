{den, ...}: let
  port = 8086;
in {
  den.aspects.services.sonarr = {
    endpoint = {
      subdomain = "shows";
      inherit port;
    };
    gluetun-ports = ["${toString port}:8989"];

    nixos = {
      imports = [(den.lib.homelab.via-gluetun "sonarr")];

      virtualisation.oci-containers.containers.sonarr = {
        image = "lscr.io/linuxserver/sonarr:latest@sha256:3b8c947d7fa173f70e40047d2c8d02835fb8416aeb5ae36def57d9ad15e2f906";
        volumes = ["/data/sonarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/sonarr 0775 1000 data -"
        "d /media/media/shows 2775 1000 data -"
      ];
    };
  };
}
