{
  den.aspects.services.immich = let
    port = 2283;
  in {
    endpoint = {
      subdomain = "photos";
      inherit port;
    };
    backup.paths = ["/var/lib/containers/storage/volumes/immich-db"];

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
        image = "ghcr.io/immich-app/immich-server:release@sha256:485d546a2e31d6a8b4db8423fcba5c109de8c218d93410af115fd1ccfc4352a6";
        dependsOn = ["immich-redis" "immich-db"];
        ports = ["${toString port}:2283"];
        environment.IMMICH_MACHINE_LEARNING_URL = "http://immich-ml:3003";
        environmentFiles = [config.sops.templates."immich.env".path];
        volumes = ["/data/immich/upload:/data" "/etc/localtime:/etc/localtime:ro"];
        extraOptions = [
          "--device=/dev/dri:/dev/dri"
          "--add-host=immich-db:host-gateway"
          "--add-host=immich-redis:host-gateway"
          "--add-host=immich-ml:host-gateway"
        ];
      };

      virtualisation.oci-containers.containers.immich-ml = {
        image = "ghcr.io/immich-app/immich-machine-learning:release@sha256:5b28c9352c8374b8a1ed96fbdd8d6755fea6e43510ec43fdf6538aa02ea40f56";
        ports = ["3003:3003"];
        volumes = ["immich-ml-cache:/cache"];
        environmentFiles = [config.sops.templates."immich.env".path];
      };

      virtualisation.oci-containers.containers.immich-redis = {
        image = "docker.io/valkey/valkey:9@sha256:3add1a336a920ea54770a001ab6feb3da5fceea96a40373a3a2cd469b815f0b7";
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
