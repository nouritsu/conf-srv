{den, ...}: {
  den.aspects.services.immich = let
    port = 2283;
    # the pc's cuda machine learning (conf-nixos); nothing here runs models
    ml-url = "http://pc:3003";
  in {
    endpoint = {
      subdomain = "photos";
      inherit port;
    };
    backup.paths = ["/var/lib/containers/storage/volumes/immich-db"];
    # regenerated from the originals
    backup.exclude = [
      "/data/immich/upload/thumbs"
      "/data/immich/upload/encoded-video"
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      sequencer = pkgs.writers.writePython3Bin "immich-ml-sequencer" {
        flakeIgnore = ["E501"];
      } (builtins.readFile ./immich-ml-sequencer.py);
    in {
      imports = [(den.lib.homelab.private-network "immich" ["immich-server" "immich-redis" "immich-db"])];

      sops.secrets."photos/postgres-password" = {};
      # an admin's key with only queue.read and queue.update
      sops.secrets."photos/sequencer-api-key" = {};

      sops.templates."immich.env" = {
        content = ''
          DB_PASSWORD=${config.sops.placeholder."photos/postgres-password"}
          DB_HOSTNAME=immich-db
          DB_PORT=5434
          DB_USERNAME=immich
          DB_DATABASE_NAME=immich
          REDIS_HOSTNAME=immich-redis
          REDIS_PORT=6379
        '';
      };

      sops.templates."immich-postgres.env" = {
        content = ''
          POSTGRES_PASSWORD=${config.sops.placeholder."photos/postgres-password"}
        '';
      };

      virtualisation.oci-containers.containers.immich-server = {
        # the pc's cuda machine learning (conf-nixos) runs this same release
        image = "ghcr.io/immich-app/immich-server:v3.3.6@sha256:e1981983b1c13f6024b57d72e7ecae3342eed1581201ab09fb248932d86c593a";
        dependsOn = ["immich-redis" "immich-db"];
        ports = ["127.0.0.1:${toString port}:2283"];
        # only the default: the admin settings' url list wins, and must hold just this too
        environment.IMMICH_MACHINE_LEARNING_URL = ml-url;
        environmentFiles = [config.sops.templates."immich.env".path];
        volumes = [
          "/data/immich/upload:/data"
          # the desktops' pictures, an external library
          "/data/sync/pictures:/external/pictures:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        extraOptions = ["--device=/dev/dri:/dev/dri"];
      };

      virtualisation.oci-containers.containers.immich-redis = {
        image = "docker.io/valkey/valkey:9@sha256:3add1a336a920ea54770a001ab6feb3da5fceea96a40373a3a2cd469b815f0b7";
        extraOptions = [
          "--health-cmd=redis-cli ping || exit 1"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=5"
        ];
      };

      virtualisation.oci-containers.containers.immich-db = {
        image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
        environment = {
          POSTGRES_USER = "immich";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
          PGPORT = "5434";
        };
        environmentFiles = [config.sops.templates."immich-postgres.env".path];
        volumes = ["immich-db:/var/lib/postgresql/data"];
        extraOptions = [
          "--shm-size=128m"
          "--health-cmd=pg_isready -U immich -p 5434"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=5"
        ];
      };

      systemd.timers.restart-container-immich-db.enable = false; # database

      # while the pc is off its queues pause, so jobs wait for it instead of failing
      systemd.services.immich-ml-sequencer = {
        description = "Run Immich's machine-learning queues one at a time while the pc is up";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target" "podman-immich-server.service"];

        serviceConfig = {
          ExecStart = "${lib.getExe sequencer} --immich http://127.0.0.1:${toString port} --ml ${ml-url}";
          DynamicUser = true;
          LoadCredential = ["api-key:${config.sops.secrets."photos/sequencer-api-key".path}"];

          Restart = "always";
          RestartSec = "1min";

          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        };
      };

      systemd.tmpfiles.rules = [
        "d /data/immich 0775 1000 data -"
        "d /data/immich/upload 0775 1000 data -"
      ];
    };
  };
}
