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
        image = "lscr.io/linuxserver/radarr:latest@sha256:51a9ac2a9eb47afc833541e5fd6c11b86eb9f810694c22fa2429e3078e9194b2";
        volumes = ["/data/radarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/radarr 0775 1000 data -"
        "d /media/media/movies 2775 1000 data -"
      ];
    };
  };
}
