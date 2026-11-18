{den, ...}: {
  den.aspects.vps = {
    includes = with den.aspects; [
      cloud
      vps.disko

      caddy
      rathole.server
      beszel-agent

      # services
      edge.www
      edge.fdroid
      edge.headscale
      edge.headplane
      edge.cn-calsync
      edge.birthdays
    ];

    nixos = {
      # ================================================================ #
      # =                         DO NOT TOUCH                         = #
      # ================================================================ #
      system.stateVersion = "23.11";

      sops.defaultSopsFile = ./secrets.yaml;
      sops.age.keyFile = "/root/sops.txt";

      networking.domain = den.lib.homelab.base-domain;

      # broker inhibits a live switch from dbus; move with `deploy vps boot` and a reboot
      services.dbus.implementation = "dbus";
    };
  };
}
