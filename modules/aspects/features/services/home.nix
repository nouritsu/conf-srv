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
      config,
      pkgs,
      ...
    }: {
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
        "d /data/homeassistant/nix/packages 0775 1000 data -"
        "d /data/homeassistant/nix/dashboards 0775 1000 data -"
        # jinja macros templates import, such as the speaker's clock times
        "d /data/homeassistant/custom_templates 0775 1000 data -"
        # the speaker's voice commands as audio, deleted after a week
        "d /data/homeassistant/voice-recordings 0775 1000 data 7d"
      ];

      # the bin calendar's source, which names the address; the rest of the bins
      # are in packages/speaker.yaml
      sops.secrets."homeassistant/bins-street" = {};
      sops.secrets."homeassistant/bins-house-number" = {};
      sops.templates."ha-bins.yaml".content = ''
        waste_collection_schedule:
          sources:
            - name: c_trace_de
              args:
                service: bremenabfallkalender
                ort: Bremen
                strasse: "${config.sops.placeholder."homeassistant/bins-street"}"
                hausnummer: "${config.sops.placeholder."homeassistant/bins-house-number"}"
      '';

      # copied, not mounted: the image chowns /config on start, which fails on the store
      systemd.services.podman-home-assistant.preStart = let
        tapo = "/data/homeassistant/custom_components/tapo";
        patch = "${pkgs.gnupatch}/bin/patch -s -f -p1 --no-backup-if-mismatch -d ${tapo}";
        one-request = ./home/tapo-one-request.patch;
        # Die Bremer Stadtreinigung's calendar; from here rather than hacs, as
        # its configuration is the yaml above
        waste-collection = pkgs.fetchFromGitHub {
          owner = "mampfes";
          repo = "hacs_waste_collection_schedule";
          rev = "v2.36.0";
          hash = "sha256-uCWvglnDeJ4/QE1+gnLqM4i6tb5XVb7aQDQC3xOZjfg=";
        };
        components = "/data/homeassistant/custom_components";
      in ''
        install -m 0444 -o 1000 -g data ${./home/configuration.yaml} /data/homeassistant/configuration.yaml
        install -m 0444 -o 1000 -g data ${./home/automations.yaml} /data/homeassistant/nix/automations.yaml
        install -m 0444 -o 1000 -g data ${./home/scenes.yaml} /data/homeassistant/nix/scenes.yaml
        install -m 0444 -o 1000 -g data ${./home/packages/speaker.yaml} /data/homeassistant/nix/packages/speaker.yaml
        install -m 0444 -o 1000 -g data ${./home/dashboards/overview.yaml} /data/homeassistant/nix/dashboards/overview.yaml
        install -m 0444 -o 1000 -g data ${./home/custom_templates/speaker.jinja} /data/homeassistant/custom_templates/speaker.jinja
        install -m 0440 -o 1000 -g data ${config.sops.templates."ha-bins.yaml".path} /data/homeassistant/nix/packages/bins.yaml

        rm -rf ${components}/waste_collection_schedule
        cp -r --no-preserve=mode ${waste-collection}/custom_components/waste_collection_schedule ${components}/
        chown -R 1000:data ${components}/waste_collection_schedule

        # hacs owns the tapo integration, which sends power, colour and brightness as three steps; patched it sends one
        if [ -f ${tapo}/light.py ]; then
          if ${patch} -R --dry-run < ${one-request} > /dev/null; then
            :
          elif ${patch} --dry-run < ${one-request} > /dev/null; then
            ${patch} < ${one-request} && echo "tapo: one-request patch applied"
          else
            echo "tapo: light.py changed upstream, one-request patch skipped"
          fi
        fi
      '';

      systemd.timers.restart-container-home-assistant.enable = false; # database
    };
  };
}
