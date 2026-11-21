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
        image = "lscr.io/linuxserver/sonarr:latest@sha256:339814bbf50599ac3b59077c252f29833d0138b59a062d0e82ce37bdc7f04f86";
        volumes = ["/data/sonarr:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/sonarr 0775 1000 data -"
        "d /media/media/shows 2775 1000 data -"
      ];
    };
  };
}
