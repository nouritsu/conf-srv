{
  # the ssd's led stays off; set once at boot, it holds until power is lost
  den.aspects.services.openrgb.nixos = {
    pkgs,
    lib,
    ...
  }: {
    systemd.services.openrgb-off = {
      description = "Switch the SSD's LED off";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe pkgs.openrgb} --noautoconnect --mode off";
      };
    };

    # root needs no rules, but openrgb warns on every run without them
    services.udev.packages = [pkgs.openrgb];

    boot.kernelModules = ["i2c-dev"];
  };
}
