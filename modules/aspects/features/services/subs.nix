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
        image = "lscr.io/linuxserver/bazarr:latest@sha256:7ef0e58216900dbce30b123e0eb65f5cb30e36f126de9474acdd2022fb069c54";
        volumes = ["/data/bazarr:/config" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = ["d /data/bazarr 0775 1000 data -"];
    };
  };
}
