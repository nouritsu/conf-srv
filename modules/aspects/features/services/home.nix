{
  den.aspects.services.homeassistant = let
    port = 8123;
  in {
    endpoint = {
      subdomain = "home";
      inherit port;
    };

    nixos = {
      virtualisation.oci-containers.containers.home-assistant = {
        image = "lscr.io/linuxserver/homeassistant:latest@sha256:abc052d76efa30451f6e4777294f49bef84df83f29d16f255e5c76ee6343c366";
        # no ports: --net=host publishes nothing, podman discards them
        extraOptions = ["--net=host" "--cap-add=NET_ADMIN" "--cap-add=NET_RAW"];
        volumes = ["/data/homeassistant:/config" "/run/dbus:/run/dbus:ro" "/proc:/host/proc:ro"];
      };

      systemd.tmpfiles.rules = ["d /data/homeassistant 0775 1000 data -"];
    };
  };
}
