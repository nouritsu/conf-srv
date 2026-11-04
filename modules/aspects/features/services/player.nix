{
  den.aspects.services.jellyfin = let
    port = 8096;
  in {
    endpoint = {
      subdomain = "player";
      inherit port;
    };
    backup.exclude = [
      "/data/jellyfin/cache"
      "/data/jellyfin/log"
      "/data/jellyfin/data/temp"
      "/data/jellyfin/data/transcodes"
    ];

    nixos = {
      virtualisation.oci-containers.containers.jellyfin = {
        image = "lscr.io/linuxserver/jellyfin:latest@sha256:b7eabe1f098f4e850bfd63d6721369117195410a471db1a41748ab768b81a639";
        ports = ["${toString port}:8096"];
        extraOptions = ["--device=/dev/dri:/dev/dri"];
        volumes = ["/data/jellyfin:/config" "/media/media:/media:ro"];
      };

      systemd.tmpfiles.rules = ["d /data/jellyfin 0775 1000 data -"];
    };
  };
}
