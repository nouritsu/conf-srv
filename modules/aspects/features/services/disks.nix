{
  den.aspects.services.scrutiny = let
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

    nixos = {
      services.udev.extraRules = ''
        SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="TOSHIBA_DT01ACA100_000000123ADC-0:0", SYMLINK+="hdd-1tb"
        SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_SERIAL}=="ST2000VM_003-1ET164_000000123ADC-0:0", SYMLINK+="hdd-2tb"
      '';

      virtualisation.oci-containers.containers.scrutiny = {
        image = "ghcr.io/starosdev/scrutiny:latest-omnibus@sha256:7de1b17227943610c4777d4d57ef1d7bbe9bcbcccc97e3b24bbc5ae3a4d8f725";
        ports = ["${toString port}:8080" "8187:8086"];
        extraOptions = ["--cap-add=SYS_ADMIN" "--cap-add=SYS_RAWIO"];
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
