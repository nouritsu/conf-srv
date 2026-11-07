{
  # consumes the `gluetun-ports` quirk: every port a service behind this vpn
  # container needs published
  den.aspects.gluetun.nixos = {
    gluetun-ports,
    config,
    lib,
    ...
  }: {
    sops.secrets."airvpn/wg-key" = {};
    sops.secrets."airvpn/wg-preshared-key" = {};
    sops.templates."gluetun.env" = {
      content = ''
        WIREGUARD_PRIVATE_KEY=${config.sops.placeholder."airvpn/wg-key"}
        WIREGUARD_PRESHARED_KEY=${config.sops.placeholder."airvpn/wg-preshared-key"}
      '';
    };

    virtualisation.oci-containers.containers.gluetun = {
      image = "qmcgaw/gluetun:latest@sha256:78c09588169ad05b9f88bc492ac8f80e6167e93da7526171863c0dfb88bf18d6";
      environment = {
        VPN_SERVICE_PROVIDER = "airvpn";
        VPN_TYPE = "wireguard";
        WIREGUARD_ADDRESSES = "10.168.189.140/32";
        SERVER_COUNTRIES = "Switzerland";
        FIREWALL_VPN_INPUT_PORTS = "59610";
      };
      environmentFiles = [config.sops.templates."gluetun.env".path];
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
        "--device=/dev/net/tun:/dev/net/tun"
        # the image declares none, and gluetun's own misses a wedged dns forwarder
        "--health-cmd=/gluetun-entrypoint healthcheck && nslookup -timeout=3 -retry=1 github.com 127.0.0.1 >/dev/null"
        "--health-interval=5s"
        "--health-timeout=5s"
        # a minute, so gluetun's own vpn restarts don't trip it
        "--health-retries=12"
        # a dead tunnel gets killed and restarted rather than left unhealthy
        "--health-on-failure=kill"
      ];
      # started means tunnel up, so nothing behind it runs before the firewall
      podman.sdnotify = "healthy";
      ports =
        ["8888:8888" "8388:8388" "59610:59610" "59610:59610/udp"]
        ++ lib.sort (a: b: a < b) gluetun-ports;
    };

    # a vpn that never comes up fails the start instead of hanging a deploy
    systemd.services.podman-gluetun.serviceConfig.TimeoutStartSec = lib.mkForce "3min";

    systemd.timers.restart-container-gluetun.enable = false; # vpn
  };
}
