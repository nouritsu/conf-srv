# speech for Home Assistant's Assist, which the speaker (github:nouritsu/ha-speaker)
# talks to; both listen on 127.0.0.1 only, for the Wyoming integration of the
# host-networked home-assistant container
{...}: {
  den.aspects.services.voice = let
    piper-port = 10200;
    speech-to-phrase-port = 10300;
  in {
    nixos = {config, ...}: {
      # text to speech; the voice is fetched on first start
      services.wyoming.piper.servers.assist = {
        enable = true;
        voice = "en_US-lessac-medium";
        uri = "tcp://127.0.0.1:${toString piper-port}";
      };

      # speech to text for a closed set of phrases: the names Home Assistant
      # exposes to Assist and the sentences its automations trigger on, which
      # it reads with this token and trains a model on at start; fast on a Pi
      # where whisper takes seconds. nixpkgs has no module for it, and the
      # homelab's nixpkgs no package
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
              --retrain-on-start
          ''
        ];
        volumes = ["/data/speech-to-phrase/models:/models" "/data/speech-to-phrase/train:/train"];
        # Home Assistant listens on the host's network
        extraOptions = ["--network=host"];
        dependsOn = ["home-assistant"];
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
