{
  den.aspects.services.immich = let
    port = 2283;
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

    nixos = {config, ...}: {
      sops.secrets."photos/postgres-password" = {};

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
        ports = ["${toString port}:2283"];
        # only the fallback: the admin settings list http://pc:3003 ahead of it
        environment.IMMICH_MACHINE_LEARNING_URL = "http://immich-ml:3003";
        environmentFiles = [config.sops.templates."immich.env".path];
        volumes = [
          "/data/immich/upload:/data"
          # the desktops' pictures, an external library
          "/data/sync/pictures:/external/pictures:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--add-host=immich-db:host-gateway"
          "--add-host=immich-redis:host-gateway"
          "--add-host=immich-ml:host-gateway"
        ];
      };

      virtualisation.oci-containers.containers.immich-ml = {
        image = "ghcr.io/immich-app/immich-machine-learning:v3.3.6@sha256:14367bfb374b8576ddf49abd67c5ca0190a4c7fcf6303cdad65d7f7bf1a50bc2";
        ports = ["3003:3003"];
        volumes = ["immich-ml-cache:/cache"];
        environmentFiles = [config.sops.templates."immich.env".path];
      };

      virtualisation.oci-containers.containers.immich-redis = {
        image = "docker.io/valkey/valkey:9@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd";
        ports = ["6379:6379"];
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
        ports = ["5434:5434"];
        extraOptions = [
          "--shm-size=128m"
          "--health-cmd=pg_isready -U immich -p 5434"
          "--health-interval=10s"
          "--health-timeout=5s"
          "--health-retries=5"
        ];
      };

      systemd.timers.restart-container-immich-db.enable = false; # database

      systemd.tmpfiles.rules = [
        "d /data/immich 0775 1000 data -"
        "d /data/immich/upload 0775 1000 data -"
      ];
    };
  };
}
