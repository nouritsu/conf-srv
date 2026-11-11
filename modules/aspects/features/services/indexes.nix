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
        image = "lscr.io/linuxserver/prowlarr:latest@sha256:6660787a99b2e58203539583663c973b48979fc00ff2cb78dc0ea17429e1f6ef";
        volumes = ["/data/prowlarr:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/prowlarr 0775 1000 data -"];
    };
  };
}
