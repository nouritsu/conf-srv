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
      # GLaDOS: a fan Piper voice trained on the Portal games' lines
      # (CC BY 4.0 by its card, but Valve's recordings; for home use only).
      # Piper names a voice by its config's "dataset", which this one leaves
      # empty, and files it under "language.code", which here is en-us where
      # Piper's own voices use en_US; both are set so Home Assistant lists it
      # with the other English voices
      glados-voice = let
        base = "https://huggingface.co/DavesArmoury/GLaDOS_TTS/resolve/b64622ad52f15804249f7f08a4c268b5e82c6969";
        model = pkgs.fetchurl {
          url = "${base}/glados_piper_medium.onnx";
          hash = "sha256-s1oH+m/HiOxK1jfsmLdNZvBuZku7Q2a0A10d6qwzCNM=";
        };
        voice-config = pkgs.fetchurl {
          url = "${base}/glados_piper_medium.onnx.json";
          hash = "sha256-d6EDN3yXHoe/rGqDm+sN6VQz84rPH7ksIB3Nxyhi9CI=";
        };
      in
        pkgs.runCommand "piper-voice-en-glados" {nativeBuildInputs = [pkgs.jq];} ''
          mkdir $out
          ln -s ${model} $out/en_US-glados-medium.onnx
          jq '.dataset = "en_US-glados-medium" | .audio.quality = "medium" | .language.code = "en_US"' ${voice-config} \
            > $out/en_US-glados-medium.onnx.json
        '';
    in {
      # text to speech, in GLaDOS' voice from the store; Home Assistant can
      # still ask for any other Piper voice, which is fetched on first use
      services.wyoming.piper.servers.assist = {
        enable = true;
        voice = "en_US-glados-medium";
        uri = "tcp://127.0.0.1:${toString piper-port}";
        extraArgs = ["--data-dir" "${glados-voice}"];
      };

      # speech to text for a closed set of phrases: the names Home Assistant
      # exposes to Assist and the sentences its automations trigger on, which
      # it reads with this token. It trains at start for each language an
      # assistant uses, and every 2 minutes looks again, retraining only if
      # a name, sentence or language changed. Fast on a Pi where whisper
      # takes seconds. nixpkgs has no module for it, and the homelab's
      # nixpkgs no package
      sops.secrets."homeassistant/speech-to-phrase-token" = {};
      sops.templates."speech-to-phrase.env".content = ''
        HASS_TOKEN=${config.sops.placeholder."homeassistant/speech-to-phrase-token"}
      '';

      virtualisation.oci-containers.containers.speech-to-phrase = {
        image = "rhasspy/wyoming-speech-to-phrase:1.4.3@sha256:85580e14114b866f5ccd6ed856b0b97f634d8d0936ed7e31edc7822840327422";
        environmentFiles = [config.sops.templates."speech-to-phrase.env".path];
        # the image's run.sh passes these on; a later --uri overrides its own
        entrypoint = "bash";
        # Home Assistant answers on its websocket before it has loaded the
        # automations whose sentences this learns, and training then would
        # leave them out; it waits until Home Assistant says it is running
        cmd = [
          "-c"
          ''
            until /usr/src/.venv/bin/python3 -c '
            import json, os, urllib.request as r
            q = r.Request("http://127.0.0.1:8123/api/config", headers={"Authorization": "Bearer " + os.environ["HASS_TOKEN"]})
            raise SystemExit(json.load(r.urlopen(q, timeout=5)).get("state") != "RUNNING")
            ' 2>/dev/null; do sleep 5; done
            exec bash /run.sh \
              --uri tcp://127.0.0.1:${toString speech-to-phrase-port} \
              --hass-websocket-uri ws://127.0.0.1:8123/api/websocket \
              --hass-token "$HASS_TOKEN" \
              --retrain-on-start \
              --retrain-seconds 120
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
