{den, ...}: let
  port = 8088;
in {
  den.aspects.services.bazarr = {
    endpoint = {
      subdomain = "subs";
      inherit port;
    };
    gluetun-ports = ["${toString port}:6767"];

    nixos = {
      imports = [(den.lib.homelab.via-gluetun "bazarr")];

      virtualisation.oci-containers.containers.bazarr = {
        image = "lscr.io/linuxserver/bazarr:latest@sha256:832820dec70bce9e912c6eee7a95baf6551e03dbc63325a7208daaa455423752";
        volumes = ["/data/bazarr:/config" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = ["d /data/bazarr 0775 1000 data -"];
    };
  };
}
