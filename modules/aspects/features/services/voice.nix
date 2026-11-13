# speech for Home Assistant's Assist, which the speaker (github:nouritsu/ha-speaker)
# talks to; both listen on 127.0.0.1 only, for the Wyoming integration of the
# host-networked home-assistant container
{...}: {
  den.aspects.services.voice = let
    piper-port = 10200;
    speech-to-phrase-port = 10300;
  in {
    nixos = {
      config,
      pkgs,
      ...
    }: let
      # GLaDOS in German: a fan voice fine-tuned from Thorsten on the German
      # Portal games' lines (unlicensed, Valve's recordings; for home use only)
      glados-voice = let
        base = "https://huggingface.co/systemofapwne/piper-de-glados/resolve/f0ee29dfa468cbc69bac1408dd3887611fcb76c1/de/de_DE/glados/medium";
      in
        pkgs.linkFarm "piper-voice-de-glados" [
          {
            name = "de_DE-glados-medium.onnx";
            path = pkgs.fetchurl {
              url = "${base}/de_DE-glados-medium.onnx";
              hash = "sha256-o/VxbhvYbGk7cy5DwKPdv/iv0x2u+aUcF8W4Ex0dPRw=";
            };
          }
          {
            name = "de_DE-glados-medium.onnx.json";
            path = pkgs.fetchurl {
              url = "${base}/de_DE-glados-medium.onnx.json";
              hash = "sha256-aUQ5GCDiRIJYHIZ5Yx20/GrAs0QOJXi8VzZVp8GGhIk=";
            };
          }
        ];
    in {
      # text to speech in German, for the stops and towns the speaker names.
      # Thorsten is fetched on first start; GLaDOS comes from the store, and
      # the speaker's assistant picks between them in Home Assistant
      services.wyoming.piper.servers.assist = {
        enable = true;
        voice = "de_DE-thorsten-medium";
        uri = "tcp://127.0.0.1:${toString piper-port}";
        extraArgs = ["--data-dir" "${glados-voice}"];
      };

      # speech to text for a closed set of phrases: the names Home Assistant
      # exposes to Assist and the sentences its automations trigger on, which
      # it reads with this token. It trains at start for each language an
      # assistant uses (German for the speaker), and every 10 minutes looks
      # again, retraining only if a name, sentence or language changed. Fast
      # on a Pi where whisper takes seconds. nixpkgs has no module for it,
      # and the homelab's nixpkgs no package
      sops.secrets."homeassistant/speech-to-phrase-token" = {};
      sops.templates."speech-to-phrase.env".content = ''
        HASS_TOKEN=${config.sops.placeholder."homeassistant/speech-to-phrase-token"}
      '';

      virtualisation.oci-containers.containers.speech-to-phrase = {
        image = "rhasspy/wyoming-speech-to-phrase:1.4.3@sha256:85580e14114b866f5ccd6ed856b0b97f634d8d0936ed7e31edc7822840327422";
        environmentFiles = [config.sops.templates."speech-to-phrase.env".path];
        # the image's run.sh passes these on; a later --uri overrides its own
        entrypoint = "bash";
        cmd = [
          "-c"
          ''
            exec bash /run.sh \
              --uri tcp://127.0.0.1:${toString speech-to-phrase-port} \
              --hass-websocket-uri ws://127.0.0.1:8123/api/websocket \
              --hass-token "$HASS_TOKEN" \
              --retrain-on-start \
              --retrain-seconds 600
          ''
        ];
        volumes = ["/data/speech-to-phrase/models:/models" "/data/speech-to-phrase/train:/train"];
        # Home Assistant listens on the host's network
        extraOptions = ["--network=host"];
        dependsOn = ["home-assistant"];
      };

      # Home Assistant listens a minute or so after its container starts, and
      # until then speech-to-phrase exits; it keeps trying instead of giving up
      # after five quick restarts
      systemd.services.podman-speech-to-phrase = {
        serviceConfig.RestartSec = "30s";
        unitConfig.StartLimitIntervalSec = 0;
      };

      # owned like /data itself: tmpfiles won't create folders inside a root
      # owned one there ("unsafe path transition")
      systemd.tmpfiles.rules = [
        "d /data/speech-to-phrase 0775 1000 data -"
        "d /data/speech-to-phrase/models 0775 1000 data -"
        "d /data/speech-to-phrase/train 0775 1000 data -"
      ];
    };
  };
}
