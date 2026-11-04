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
        image = "lscr.io/linuxserver/prowlarr:latest@sha256:431d7efebcef466e56adaa40a7a2fa2b0e85159a037b8bf465eaadbf0cf5bedf";
        volumes = ["/data/prowlarr:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/prowlarr 0775 1000 data -"];
    };
  };
}
