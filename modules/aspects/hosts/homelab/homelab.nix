{
  inputs,
  den,
  ...
}: {
  den.aspects.homelab = {
    includes = with den.aspects; [
      server
      backup
      network.manager

      # hardware
      graphics
      storage
      homelab.disko

      # services
      services.openrgb
      services.beszel
      services.copyparty
      services.bindery
      services.bazarr
      services.scrutiny
      services.paperless
      services.homeassistant
      services.prowlarr
      services.tailscale
      services.radarr
      services.pihole
      services.jellyfin
      services.enclosed
      services.sonarr
      services.documenso
      services.syncthing
      services.qbittorrent
      services.mousehole
      services.sabnzbd
      services.radicale
      services.atuin
      services.immich
    ];

    nixos = {pkgs, ...}: {
      imports = let
        rpinm = inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5;
      in
        with rpinm; [
          base
          display-vc4
          bluetooth
        ];

      # ================================================================ #
      # =                         DO NOT TOUCH                         = #
      # ================================================================ #
      system.stateVersion = "25.11";

      sops.defaultSopsFile = ./secrets.yaml;

      networking.domain = den.lib.homelab.base-domain;

      boot.loader.raspberry-pi.bootloader = "kernel";
      environment.systemPackages = [pkgs.raspberrypi-eeprom];

      # off data's 993, which the pi's first activation had already given spi
      users.groups.spi.gid = 973;

      # the bcm2835 watchdog's maximum; a hung pi resets itself
      systemd.settings.Manager.RuntimeWatchdogSec = "15s";

      # zram first, the nvme swapfile only as overflow
      zramSwap.enable = true;
      swapDevices = [
        {
          device = "/swap/swapfile";
          size = 8 * 1024;
          priority = 0;
        }
      ];

      # own subvolume: btrfs won't snapshot one holding an active swapfile
      systemd.services.mkswap-swap-swapfile.preStart = ''
        [ -e /swap ] || btrfs subvolume create /swap
      '';
    };
  };
}
