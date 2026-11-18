{den, ...}: let
  port = 8787;
in {
  den.aspects.services.bindery = {
    endpoint = {
      subdomain = "books";
      inherit port;
    };
    gluetun-ports = ["${toString port}:8787"];

    nixos = {config, ...}: {
      imports = [(den.lib.homelab.via-gluetun "bindery")];

      virtualisation.oci-containers.containers.bindery = {
        image = "ghcr.io/vavallee/bindery:v1.52.0@sha256:100091a1d8247e1f5d0ea8c243b703da5398afa9caa7d3aea237ad4fa468e4d0";
        # distroless: the uid comes from --user, not PUID/PGID
        extraOptions = ["--user=1000:${toString config.users.groups.data.gid}"];
        environment = {
          BINDERY_LIBRARY_DIR = "/media/books";
          # also the save path it hands qbittorrent
          BINDERY_DOWNLOAD_DIR = "/data/torrent/complete/books";
          # prowlarr's download links are loopback inside gluetun's netns
          BINDERY_DOWNLOAD_ALLOW_LOOPBACK = "true";
        };
        volumes = ["/data/bindery:/config" "/media/download:/data" "/media/media:/media"];
      };

      systemd.tmpfiles.rules = [
        "d /data/bindery 0775 1000 data -"
        "d /media/media/books 2775 1000 data -"
      ];
    };
  };
}
