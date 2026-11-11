{den, ...}: {
  den.aspects.services.homeassistant = let
    inherit (den.lib.homelab) lan-interface lan-cidr;
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
        # podman's default 10 s killed hass mid-shutdown; 90 s stays under systemd's 2 min
        extraOptions = ["--net=host" "--cap-add=NET_ADMIN" "--cap-add=NET_RAW" "--stop-timeout=90"];
        volumes = ["/data/homeassistant:/config" "/run/dbus:/run/dbus:ro" "/proc:/host/proc:ro"];
      };

      # --net=host skips podman's own rules; sonos pushes events to 1400, mdns and ssdp find devices
      networking.firewall.interfaces.${lan-interface} = {
        allowedTCPPorts = [port 1400];
        allowedUDPPorts = [5353 1900];
      };

      # ssdp replies come from 1900 to whatever port hass searched from; sonos discovery only uses them
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -i ${lan-interface} -s ${lan-cidr} -p udp --sport 1900 -j nixos-fw-accept
      '';

      systemd.tmpfiles.rules = [
        "d /data/homeassistant 0775 1000 data -"
        "d /data/homeassistant/nix 0775 1000 data -"
      ];

      # copied, not mounted: the image chowns /config on start, which fails on the store
      systemd.services.podman-home-assistant.preStart = ''
        install -m 0444 -o 1000 -g data ${./home/configuration.yaml} /data/homeassistant/configuration.yaml
        install -m 0444 -o 1000 -g data ${./home/automations.yaml} /data/homeassistant/nix/automations.yaml
        install -m 0444 -o 1000 -g data ${./home/scenes.yaml} /data/homeassistant/nix/scenes.yaml
      '';

      systemd.timers.restart-container-home-assistant.enable = false; # database
    };
  };
}
