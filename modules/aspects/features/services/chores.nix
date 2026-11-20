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
        image = "lscr.io/linuxserver/grocy:latest@sha256:ef5ea5094aa2ed32df74528c4bdd94713679038c97add02045d881550c2a59a8";
        ports = ["${toString port}:80"];
        volumes = ["/data/grocy:/config"];
      };

      systemd.tmpfiles.rules = ["d /data/grocy 0775 1000 data -"];
    };
  };
}
