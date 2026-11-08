{
  den.aspects.services.grocy = let
    port = 9283;
  in {
    endpoint = {
      subdomain = "chores";
      inherit port;
    };

    nixos = {
      virtualisation.oci-containers.containers.grocy = {
        image = "lscr.io/linuxserver/grocy:latest@sha256:e4e34a0a84f407b1bcd2c3b6cd1999bf99bcad1defa8847adea7dc82a9cd6b8c";
        ports = ["${toString port}:80"];
        volumes = ["/data/grocy:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/grocy 0775 1000 data -"];
    };
  };
}
