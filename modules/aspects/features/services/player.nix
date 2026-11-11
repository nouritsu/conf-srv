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
        image = "lscr.io/linuxserver/jellyfin:latest@sha256:2f708001387aa9853e744a4a4d572d9970927c479c56d6c9e199f789c5173535";
        ports = ["${toString port}:8096"];
        extraOptions = ["--device=/dev/dri:/dev/dri"];
        volumes = ["/data/jellyfin:/config" "/media/media:/media:ro"];
      };

      systemd.tmpfiles.rules = ["d /data/jellyfin 0775 1000 data -"];
    };
  };
}
