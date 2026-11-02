let
  port = 2222;
in {
  # hollow knight multiplayer
  den.aspects.games.hkmp.nixos = {
    virtualisation.oci-containers.containers.hkmp = {
      image = "maximalmax90/hkmpserver:latest@sha256:9d5e68e21564a258578d17802a5e0bc6e86f8cf731e295f0b5371e9a63e1e5b6";
      ports = ["${toString port}:${toString port}/udp"];
      environment.PORT = toString port;
      volumes = ["/data/hkmp:/HKMP"];
    };

    systemd.tmpfiles.rules = [
      "d /data/hkmp 0755 root root - -"
    ];

    networking.firewall.allowedUDPPorts = [port];
  };
}
