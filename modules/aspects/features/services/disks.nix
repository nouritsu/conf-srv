{den, ...}: {
  den.aspects.services.scrutiny = let
    inherit (den.lib.homelab) smtp;
    port = 8180;

    root = "/dev/nvme0n1";

    # sda/sdb swap between boots, and podman's --device can't take the ':' in by-id names
    hdd-1tb = "/dev/hdd-1tb";
    hdd-2tb = "/dev/hdd-2tb";
  in {
    endpoint = {
      subdomain = "disks";
      inherit port;
    };

    nixos = {config, ...}: {
      sops.secrets."mail/address" = {};
      sops.secrets."mail/token" = {};
      sops.secrets."mail/admin".sopsFile = den.lib.homelab.shared-secrets;
      sops.templates."scrutiny.env".content = let
        address = config.sops.placeholder."mail/address";
      in ''
        SCRUTINY_NOTIFY_URLS=smtp://${address}:${config.sops.placeholder."mail/token"}@${smtp.host}:${toString smtp.port}/?auth=Plain&encryption=ExplicitTLS&from=${address}&to=${config.sops.placeholder."mail/admin"}
      '';

      services.udev.extraRules = ''
        SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="TOSHIBA_DT01ACA100_000000123ADC-0:0", SYMLINK+="hdd-1tb"
        SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="ST2000VM_003-1ET164_000000123ADC-0:0", SYMLINK+="hdd-2tb"
      '';

      virtualisation.oci-containers.containers.scrutiny = {
        image = "ghcr.io/starosdev/scrutiny:latest-omnibus@sha256:614f2805b0e76565463ce3d5e400ebe4a1e7f3989877f4cb092eba00137067ba";
        ports = ["${toString port}:8080" "8187:8086"];
        extraOptions = ["--cap-add=SYS_ADMIN" "--cap-add=SYS_RAWIO"];
        # influxdb backed up to /data/scrutiny/influxdb.pre-2.9 on 2026-11-12
        environment.SCRUTINY_INFLUXDB_29_BACKUP_CONFIRMED = "true";
        environmentFiles = [config.sops.templates."scrutiny.env".path];
        devices = ["${hdd-1tb}:/dev/sda" "${hdd-2tb}:/dev/sdb" root];
        volumes = [
          "/run/udev:/run/udev:ro"
          "/data/scrutiny/config:/opt/scrutiny/config"
          "/data/scrutiny/influxdb:/opt/scrutiny/influxdb"
        ];
      };

      systemd.tmpfiles.rules = [
        "d /data/scrutiny 0755 root root -"
        "d /data/scrutiny/config 0755 root root -"
        "d /data/scrutiny/influxdb 0755 root root -"
      ];
    };
  };
}
