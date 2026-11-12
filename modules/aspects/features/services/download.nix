{den, ...}: let
  web-port = 6880;
  rpc-port = 6800;
in {
  den.aspects.services.aria2 = {
    # two endpoints: the web ui is published directly, the rpc port through gluetun
    endpoint = [
      {
        subdomain = "download";
        port = web-port;
      }
      {
        subdomain = "aria2";
        port = rpc-port;
      }
    ];
    gluetun-ports = ["${toString rpc-port}:6800"];

    nixos = {config, ...}: {
      imports = [(den.lib.homelab.via-gluetun "aria2-pro")];

      sops.secrets."aria2/rpc" = {};
      sops.templates."aria2.env" = {
        content = ''
          RPC_SECRET=${config.sops.placeholder."aria2/rpc"}
        '';
      };

      virtualisation.oci-containers.containers.aria2-pro = {
        image = "p3terx/aria2-pro:latest@sha256:086d1a37c586edb07ec0fb956bf9edd89d1d38d138ad5309ff96d510c8c9a011";
        environment = {
          PUID = "1000";
          PGID = "1000";
          UPDATE_TRACKERS = "false";
        };
        environmentFiles = [config.sops.templates."aria2.env".path];
        volumes = ["/data/ariang/config:/config" "/media/download/aria2:/downloads"];
        extraOptions = ["--log-driver=json-file" "--log-opt=max-size=1m"];
      };

      virtualisation.oci-containers.containers.ariang = {
        image = "p3terx/ariang:latest@sha256:cba2c964c997d2ea0d615621e7846c79386f06a8f6079eabbeda52373cf2f374";
        ports = ["${toString web-port}:6880"];
        extraOptions = ["--log-driver=json-file" "--log-opt=max-size=1m"];
      };

      systemd.tmpfiles.rules = [
        "d /data/ariang 0775 1000 data -"
        "d /data/ariang/config 0775 1000 data -"
        "d /media/download/aria2 2775 1000 data -"
      ];
    };
  };
}
