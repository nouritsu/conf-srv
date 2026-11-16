{den, ...}: let
  inherit (den.lib.homelab) host-ip lan-interface;

  port = 51821;
  wg-port = 51820;
  data-dir = "/data/wg-easy";
in {
  den.aspects.services.wg-easy = {
    endpoint = {
      subdomain = "vpn";
      inherit port;
    };

    nixos = {config, ...}: {
      sops.secrets."wireguard/server-public-ip" = {};
      sops.secrets."wireguard/easy-password" = {};
      sops.templates."wg-easy.env" = {
        content = ''
          INIT_HOST=${config.sops.placeholder."wireguard/server-public-ip"}
          INIT_PASSWORD=${config.sops.placeholder."wireguard/easy-password"}
        '';
      };

      virtualisation.oci-containers.containers.wg-easy = {
        image = "ghcr.io/wg-easy/wg-easy:15@sha256:071f79a639e9361123a5e57733107320207b844ddbbd92dfa6962f541fe8aac8";
        environment = {
          INIT_ENABLED = "true";
          INIT_USERNAME = "admin";
          INIT_DNS = "${host-ip},1.1.1.1";
          WG_POST_UP = "";
          WG_POST_DOWN = "";
        };
        environmentFiles = [config.sops.templates."wg-easy.env".path];
        volumes = [
          "${data-dir}:/etc/wireguard"
          "/run/booted-system/kernel-modules/lib/modules:/lib/modules:ro"
        ];
        # no ports: --network=host publishes nothing, podman discards them.
        # The firewall rule below is what actually opens the wireguard port.
        extraOptions = ["--privileged" "--network=host"];
      };

      systemd.timers.restart-container-wg-easy.enable = false; # vpn
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv4.conf.all.src_valid_mark" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        "net.ipv6.conf.default.forwarding" = 1;
      };
      networking.nat = {
        enable = true;
        enableIPv6 = true;
        externalInterface = lan-interface;
        internalInterfaces = ["wg0"];
      };
      networking.firewall = {
        allowedUDPPorts = [wg-port];
        trustedInterfaces = ["wg0"];
      };
      systemd.tmpfiles.rules = ["d ${data-dir} 0700 root root -"];
    };
  };
}
