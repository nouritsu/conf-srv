let
  root = "/srv/fdroid";
in {
  # the f-droid repo for nouritsu/fast-track: fdroidserver's static files, which that
  # repo's release workflow builds and rsyncs in. clients add fdroid.nouritsu.com/repo
  den.aspects.edge.fdroid = {
    endpoint = {
      subdomain = "fdroid";
      public = true;
      # clients revalidate the indexes on every fetch, so a release shows at once; an
      # apk's name carries its version, so it never changes
      extraConfig = ''
        root * ${root}
        @index path */index* */entry.* */diff/*
        header @index Cache-Control "no-cache"
        @apk path *.apk
        header @apk Cache-Control "public, max-age=31536000, immutable"
        file_server
      '';
    };

    nixos = {pkgs, ...}: {
      # fast-track's github actions rsync the repo in as this user. the key may only run
      # rrsync, confined to the repo and write-only: https://man.archlinux.org/man/rrsync.1
      users.users.fdroid-deployer = {
        isNormalUser = true;
        description = "GitHub Actions F-Droid Repo Deployer";
        # sshd runs the forced command through the login shell
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = map (key: ''restrict,command="${pkgs.rrsync}/bin/rrsync -wo ${root}" ${key}'') [
          # the public half of fast-track's FDROID_SSH_KEY deploy key goes here
        ];
      };

      systemd.tmpfiles.rules = [
        "d ${root} 0750 fdroid-deployer caddy - -"
      ];
    };
  };
}
