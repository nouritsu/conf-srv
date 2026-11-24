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
      lib,
      pkgs,
      ...
    }: let
      calendars = "/data/homeassistant/nix/calendars";
      holiday-feeds = pkgs.writers.writePython3Bin "holiday-feeds" {
        libraries = with pkgs.python3Packages; [holidays icalendar];
        flakeIgnore = ["E501"];
      } (builtins.readFile ./home/holiday-feeds.py);
      # Portal 2's PA chime and PotatOS' slow clap, which the speaker plays
      # from www/speaker. Valve's sounds, so sops-encrypted in this public
      # repo. Made from portal2/pak01_dir.vpk with ffmpeg as mono 96k Opus:
      # sound/props/pre_message_announcer_01.wav as it is, and
      # sound/vo/glados/potatos_sp_a3_00_fall18, 19 and 20 joined with 0.6 s
      # and 0.8 s of silence between them
      sounds = ["announcement-chime" "slow-clap"];
      install-sounds =
        lib.concatMapStrings (s: ''
          install -m 0444 -o 1000 -g data ${config.sops.secrets."homeassistant/${s}".path} /data/homeassistant/www/speaker/${s}.ogg
        '')
        sounds;
    in {
      virtualisation.oci-containers.containers.home-assistant = {
        image = "lscr.io/linuxserver/homeassistant:latest@sha256:eb0569bc38f0910bd6bce9b813e87bc72b985aa30787f659c496a8a19d1bd8ae";
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
        # served at /local/: the speaker's sounds
        "d /data/homeassistant/www 0775 1000 data -"
        "d /data/homeassistant/www/speaker 0775 1000 data -"
        # the holiday feeds, which the calendars below read
        "d ${calendars} 0775 1000 data -"
      ];

      sops.secrets."homeassistant/announcement-chime" = {
        sopsFile = ./home/sounds/announcement-chime.ogg.enc;
        format = "binary";
      };
      sops.secrets."homeassistant/slow-clap" = {
        sopsFile = ./home/sounds/slow-clap.ogg.enc;
        format = "binary";
      };
      sops.secrets."cn-calsync/feed-token".sopsFile = den.lib.homelab.shared-secrets;

      # the calendars, from the feeds cn-calsync and radicale's birthdays
      # publish under secret tokens and from holiday-feeds below. ics_feed is
      # in custom_components; an hour between fetches, holidays four times a day
      sops.templates."ha-calendars.yaml".content = let
        campusnet = "https://${den.lib.homelab.fqdn "cal"}/${config.sops.placeholder."cn-calsync/feed-token"}";
        feed = name: url: every: ''
          - platform: ics_feed
            name: ${name}
            url: "${url}"
            scan_interval: "${every}"
        '';
      in ''
        calendar:
        ${lib.concatStrings [
          (feed "CampusNet Lectures" "${campusnet}/lectures.ics" "01:00:00")
          (feed "CampusNet Tutorials" "${campusnet}/tutorials.ics" "01:00:00")
          (feed "CampusNet Exams" "${campusnet}/exams.ics" "01:00:00")
          (feed "CampusNet Other" "${campusnet}/other.ics" "01:00:00")
          # radicale's feed-port, on the host's network as Home Assistant is
          (feed "Birthdays" "http://127.0.0.1:8089/${config.sops.placeholder."birthdays/feed-token"}/birthdays.ics" "01:00:00")
          (feed "Holidays in Bremen" "file:///config/nix/calendars/holidays-bremen.ics" "06:00:00")
          (feed "Holidays in Pune" "file:///config/nix/calendars/holidays-pune.ics" "06:00:00")
        ]}'';

      # Bremen's and Pune's holidays as ics feeds, from the holidays library:
      # once at boot or deploy, then daily, for last year to two years ahead
      systemd.services.holiday-feeds = {
        description = "Write the holidays in Bremen and Pune as ics feeds for Home Assistant";
        wantedBy = ["multi-user.target"];
        unitConfig.RequiresMountsFor = calendars;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe holiday-feeds} ${calendars}";
          DynamicUser = true;
          SupplementaryGroups = ["data"];
          ReadWritePaths = [calendars];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          PrivateNetwork = true;
          NoNewPrivileges = true;
        };
      };
      systemd.timers.holiday-feeds = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

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
        install -m 0440 -o 1000 -g data ${config.sops.templates."ha-calendars.yaml".path} /data/homeassistant/nix/packages/calendars.yaml
        ${install-sounds}
        rm -rf ${components}/waste_collection_schedule
        cp -r --no-preserve=mode ${waste-collection}/custom_components/waste_collection_schedule ${components}/
        chown -R 1000:data ${components}/waste_collection_schedule

        # the calendars' feeds, see ha-calendars.yaml
        rm -rf ${components}/ics_feed
        cp -r --no-preserve=mode ${./home/custom_components/ics_feed} ${components}/ics_feed
        chown -R 1000:data ${components}/ics_feed

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
