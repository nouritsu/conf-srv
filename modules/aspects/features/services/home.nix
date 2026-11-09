{den, ...}: {
  den.aspects.services.homeassistant = let
    inherit (den.lib.homelab) lan-interface;
    port = 8123;
  in {
    endpoint = {
      subdomain = "home";
      inherit port;
    };

    nixos = {
      virtualisation.oci-containers.containers.home-assistant = {
        image = "lscr.io/linuxserver/homeassistant:latest@sha256:6e6257d3a396177d17834bb1fea6226c62380ffab77047a0bb3e325b5421a74b";
        # no ports: --net=host publishes nothing, podman discards them
        extraOptions = ["--net=host" "--cap-add=NET_ADMIN" "--cap-add=NET_RAW"];
        volumes = ["/data/homeassistant:/config" "/run/dbus:/run/dbus:ro" "/proc:/host/proc:ro"];
      };

      # --net=host skips podman's own rules, so the lan needs the port opened
      networking.firewall.interfaces.${lan-interface}.allowedTCPPorts = [port];

      systemd.tmpfiles.rules = ["d /data/homeassistant 0775 1000 data -"];
    };
  };
}
