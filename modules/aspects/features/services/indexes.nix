{den, ...}: let
  port = 8084;
in {
  den.aspects.services.prowlarr = {
    endpoint = {
      subdomain = "indexes";
      inherit port;
    };
    gluetun-ports = ["${toString port}:9696"];

    nixos = {
      imports = [(den.lib.homelab.via-gluetun "prowlarr")];

      virtualisation.oci-containers.containers.prowlarr = {
        image = "lscr.io/linuxserver/prowlarr:latest@sha256:45117ba8439e2337a92ffe38a451a4dafc0be771754d05d88cdf102419d09646";
        volumes = ["/data/prowlarr:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/prowlarr 0775 1000 data -"];
    };
  };
}
