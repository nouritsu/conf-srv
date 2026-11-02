{den, ...}: let
  inherit (den.lib.homelab) fqdn lan-cidr lan-interface;

  # fixed so the firewall can let peers reach it directly
  port = 41641;
in {
  den.aspects.services.tailscale.nixos = {config, ...}: {
    sops.secrets."tailscale/authkey" = {};

    sops.templates."tailscale.env" = {
      content = ''
        TS_AUTHKEY=${config.sops.placeholder."tailscale/authkey"}
      '';
    };

    virtualisation.oci-containers.containers.tailscale = {
      image = "ghcr.io/tailscale/tailscale:latest@sha256:ed6480b33c6eb67c9cbd203ed42b9fb57e361986725b6856def71b7a3d9e276c";

      environment = {
        TS_STATE_DIR = "/var/lib/tailscale";
        TS_USERSPACE = "false";
        TS_TAILSCALED_EXTRA_ARGS = "--port=${toString port}";
        TS_EXTRA_ARGS = "--reset --login-server=https://${fqdn "vpn"} --advertise-routes=${lan-cidr} --accept-dns=false --netfilter-mode=off";
      };

      environmentFiles = [config.sops.templates."tailscale.env".path];

      volumes = [
        "/data/tailscale:/var/lib/tailscale"
        "/dev/net/tun:/dev/net/tun"
      ];

      extraOptions = [
        "--network=host"
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
        "--privileged"
      ];
    };

    systemd.timers.restart-container-tailscale.enable = false; # vpn

    systemd.tmpfiles.rules = [
      "d /data/tailscale 0775 1000 data -"
    ];

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # the image only speaks legacy iptables, which this kernel lacks
    networking.nat = {
      enable = true;
      externalInterface = lan-interface;
      internalInterfaces = ["tailscale0"];
    };

    networking.firewall = {
      checkReversePath = "loose";
      allowedUDPPorts = [port];
      trustedInterfaces = ["tailscale0"];
    };
  };
}
