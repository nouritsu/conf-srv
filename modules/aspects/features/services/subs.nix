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
        image = "lscr.io/linuxserver/bazarr:latest@sha256:e0c5d45965242830c5eeddaafe9ae2b5e8ca3f6c01ecda9ee9364f550921dc50";
        volumes = ["/data/bazarr:/config" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = ["d /data/bazarr 0775 1000 data -"];
    };
  };
}
