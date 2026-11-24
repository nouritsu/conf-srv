{
  # consumes the `backup` quirk: restic into the pc's append-only repo, from btrfs snapshots
  den.aspects.backup.nixos = {
    backup,
    config,
    lib,
    pkgs,
    ...
  }: let
    target = {
      host = "pc";
      user = "homelab-backup";
      repo = "/backup/homelab";
    };

    normalise = p:
      if p == "/"
      then p
      else lib.removeSuffix "/" p;
    paths = lib.unique (map normalise (lib.concatMap (b: b.paths or []) backup));
    exclude = lib.unique (lib.concatMap (b: b.exclude or []) backup);

    # the mount a path lives on: the deepest mount point above it
    mounts = lib.attrValues config.fileSystems;
    is-under = m: p: m == "/" || p == m || lib.hasPrefix "${m}/" p;
    mount-of = p:
      lib.last (lib.sortOn (m: lib.stringLength m.mountPoint)
        (lib.filter (m: is-under m.mountPoint p) mounts));

    snapshot-dir = m: "${lib.removeSuffix "/" m}/.backup-snapshot";
    in-snapshot = p: let
      m = (mount-of p).mountPoint;
    in
      snapshot-dir m + lib.removePrefix (lib.removeSuffix "/" m) p;

    on-btrfs = lib.filter (p: (mount-of p).fsType == "btrfs") paths;
    snapshotted = lib.unique (map (p: (mount-of p).mountPoint) on-btrfs);
  in {
    sops.secrets."backup/restic-password" = {};
    sops.secrets."backup/ssh-key" = {};

    programs.ssh.knownHosts.${target.host} = {
      hostNames = [target.host "${target.host}.fritz.box"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI6n+UTnGyxFYxXVzIgWcuAsCuJECEtLSB8P4JcA5LW";
    };

    # the previous run's snapshots stay until this one replaces them
    systemd.services.backup-snapshot = {
      description = "Read-only btrfs snapshots for the backup";
      serviceConfig.Type = "oneshot";
      onFailure = ["notify-failure@%n.service"];
      path = [pkgs.btrfs-progs];
      script =
        lib.concatMapStrings (m: ''
          if [ -e ${snapshot-dir m} ]; then
            btrfs subvolume delete ${snapshot-dir m}
          fi
          btrfs subvolume snapshot -r ${m} ${snapshot-dir m}
        '')
        snapshotted;
    };

    # the pc's forced command ignores the repository and rclone arguments
    services.restic.backups.${target.host} = {
      repository = "rclone:${target.host}:${target.repo}";
      passwordFile = config.sops.secrets."backup/restic-password".path;
      extraOptions = [
        "rclone.program='ssh -i ${config.sops.secrets."backup/ssh-key".path} -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=60 ${target.user}@${target.host}'"
      ];
      initialize = true;
      inherit paths;
      exclude = exclude ++ map snapshot-dir snapshotted;
    };

    systemd.services."restic-backups-${target.host}" = {
      requires = ["backup-snapshot.service"];
      after = ["backup-snapshot.service"];
      # an unmounted path fails the run instead of backing up an empty directory
      unitConfig.RequiresMountsFor = paths;
      serviceConfig = {
        # each path reads as its snapshot, at its own path, in this unit only
        BindReadOnlyPaths = map (p: "-${in-snapshot p}:${p}") on-btrfs;

        # the pc is often off; keep trying hourly until a run lands
        Restart = "on-failure";
        RestartSec = "1h";
      };
    };
  };
}
