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
        image = "lscr.io/linuxserver/sonarr:latest@sha256:c7d1df25e428da6c9ace05daea0d34e59522978a3843ea1944812f855af4086c";
        volumes = ["/data/sonarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/sonarr 0775 1000 data -"
        "d /media/media/shows 2775 1000 data -"
      ];
    };
  };
}
