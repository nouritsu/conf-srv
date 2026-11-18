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
        image = "lscr.io/linuxserver/jellyfin:latest@sha256:b10044530553b2506f06279bf0b5223f9534f434f87a277da4b8fa8ac386cb58";
        ports = ["${toString port}:8096"];
        extraOptions = ["--device=/dev/dri:/dev/dri"];
        volumes = ["/data/jellyfin:/config" "/media/media:/media:ro"];
      };

      systemd.tmpfiles.rules = ["d /data/jellyfin 0775 1000 data -"];
    };
  };
}
