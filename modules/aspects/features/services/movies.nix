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
        image = "lscr.io/linuxserver/radarr:latest@sha256:ade5937813c6ae415b29db729386e53fea3ecf067a019849bafbe2d2a6ec02ba";
        volumes = ["/data/radarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/radarr 0775 1000 data -"
        "d /media/media/movies 2775 1000 data -"
      ];
    };
  };
}
