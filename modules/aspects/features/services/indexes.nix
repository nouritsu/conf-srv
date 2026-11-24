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
        image = "lscr.io/linuxserver/prowlarr:latest@sha256:2806c9b763810589c42157730d547c293639e55c7610e9f5069314854639ec48";
        volumes = ["/data/prowlarr:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/prowlarr 0775 1000 data -"];
    };
  };
}
