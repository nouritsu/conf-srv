let
  port = 8384;
  api = "http://127.0.0.1:${toString port}";

  devices = ["homelab" "pc" "laptop" "pixel"];

  base-ignores = [
    # snapper's subvolume on the desktops; its acl lets the owner read it
    "/.snapshots"
    "(?d).directory"
    "(?d)Thumbs.db"
    "(?d).DS_Store"
    ".~lock.*#"
    "~$*"
    "*.part"
    "*.crdownload"
  ];
  # mediastore's half-written and trashed files
  phone-ignores = ["(?d).pending-*" "(?d).trashed-*" "(?d).thumbnails"];

  # the hub's copies are receive-only: only the desktops and the phone make changes
  folders = {
    documents = {
      path = "/data/sync/documents";
      devices = ["pc" "laptop"];
      ignores = base-ignores;
    };
    assignments = {
      path = "/data/sync/assignments";
      devices = ["pc" "laptop"];
      ignores =
        base-ignores
        ++ [
          "(?d).direnv"
          "(?d).devenv"
          "(?d).venv"
          "(?d)__pycache__"
          "(?d).ipynb_checkpoints"
          "(?d)node_modules"
          "(?d)target"
          "(?d)result"
        ];
    };
    pictures = {
      path = "/data/sync/pictures";
      devices = ["pc" "laptop"];
      # phone-screenshots is its own folder, nested here on the desktops
      ignores = base-ignores ++ ["/Phone"];
    };
    books = {
      path = "/data/sync/books";
      devices = ["pc" "laptop" "pixel"];
      ignores = base-ignores;
    };
    phone-screenshots = {
      path = "/data/sync/phone-screenshots";
      devices = ["pixel" "pc" "laptop"];
      ignores = phone-ignores;
    };
    # a mirror, not an archive: google photos keeps the originals
    phone-camera = {
      path = "/data/sync/phone-camera";
      devices = ["pixel" "pc" "laptop"];
      ignores = phone-ignores;
    };
    # seedvault keeps its own generations
    phone-seedvault = {
      path = "/data/sync/phone-seedvault";
      devices = ["pixel"];
      versioned = false;
    };
    # paperless would consume a .stignore as a text document
    phone-scanned-docs = {
      path = "/var/lib/paperless/consume";
      devices = ["pixel"];
      versioned = false;
    };
    # bindery's library, the one folder the hub sends
    library = {
      path = "/media/media/books";
      type = "sendonly";
      devices = ["pc" "laptop" "pixel"];
      ignores = base-ignores;
      versioned = false;
    };
  };
in {
  den.aspects.services.syncthing = {
    endpoint = {
      subdomain = "sync";
      inherit port;
    };
    # the receive-only folders too: a deletion syncs everywhere, a snapshot keeps it
    backup = {config, ...}: {
      paths =
        [config.services.syncthing.dataDir]
        ++ map (f: f.path) (builtins.filter (f: (f.type or "receiveonly") == "receiveonly") (builtins.attrValues folders));
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.services.syncthing;
      id = device: config.sops.placeholder."syncthing/ids/${device}";

      folder-json = name: f:
        {
          id = name;
          label = name;
          inherit (f) path;
          type = f.type or "receiveonly";
          devices = map (d: {deviceID = id d;}) (["homelab"] ++ f.devices);
        }
        // lib.optionalAttrs (f.versioned or true) {
          versioning = {
            type = "staggered";
            params.maxAge = toString (90 * 24 * 60 * 60);
          };
        };

      ignored = lib.filterAttrs (_: f: f ? ignores) folders;
      stignore = name: f: pkgs.writeText "${name}.stignore" (lib.concatLines f.ignores);

      # ids live in sops, so devices and folders can't go through the module's settings
      peers = pkgs.writers.writeBash "syncthing-peers" ''
        set -efu
        umask 0077

        # ignores land before a new folder's first scan
        ${lib.concatStrings (lib.mapAttrsToList (name: f: ''
            mkdir -p ${lib.escapeShellArg f.path}
            install -m644 ${stignore name f} ${lib.escapeShellArg "${f.path}/.stignore"}
          '')
          ignored)}

        (printf "X-API-Key: "; ${pkgs.libxml2}/bin/xmllint --xpath 'string(configuration/gui/apikey)' ${cfg.configDir}/config.xml) >"$RUNTIME_DIRECTORY/headers"
        curl() {
          ${lib.getExe pkgs.curl} -sS --fail-with-body -H "@$RUNTIME_DIRECTORY/headers" \
            --retry 60 --retry-connrefused --retry-delay 1 "$@"
        }

        # a put replaces the whole list; whatever it leaves out is removed
        curl -X PUT --json @${config.sops.templates."syncthing-devices.json".path} ${api}/rest/config/devices
        curl -X PUT --json @${config.sops.templates."syncthing-folders.json".path} ${api}/rest/config/folders

        ${lib.concatStrings (lib.mapAttrsToList (name: f: ''
            curl --json ${lib.escapeShellArg (builtins.toJSON {ignore = f.ignores;})} '${api}/rest/db/ignores?folder=${name}'
          '')
          ignored)}

        if curl ${api}/rest/config/restart-required | ${lib.getExe pkgs.jq} -e .requiresRestart >/dev/null; then
          curl -X POST ${api}/rest/system/restart
        fi
      '';
    in {
      sops.secrets =
        {
          "syncthing/key" = {};
          "syncthing/cert" = {};
          # syncthing-init hashes it into the gui's config as the syncthing user
          "syncthing/gui-password" = {
            owner = cfg.user;
            restartUnits = ["syncthing-init.service"];
          };
        }
        // lib.genAttrs (map (d: "syncthing/ids/${d}") devices) (_: {});

      sops.templates."syncthing-devices.json" = {
        owner = cfg.user;
        restartUnits = ["syncthing-peers.service"];
        content = builtins.toJSON (map (name: {
            deviceID = id name;
            inherit name;
            addresses = ["dynamic"];
            autoAcceptFolders = false;
            introducer = false;
          })
          devices);
      };
      sops.templates."syncthing-folders.json" = {
        owner = cfg.user;
        restartUnits = ["syncthing-peers.service"];
        content = builtins.toJSON (lib.mapAttrsToList folder-json folders);
      };

      services.syncthing = {
        enable = true;
        guiAddress = "127.0.0.1:${toString port}";
        openDefaultPorts = true;
        # copied in as root before syncthing starts; the device id survives a reinstall
        key = config.sops.secrets."syncthing/key".path;
        cert = config.sops.secrets."syncthing/cert".path;
        overrideDevices = false;
        overrideFolders = false;
        guiPasswordFile = config.sops.secrets."syncthing/gui-password".path;
        settings = {
          gui = {
            user = "admin";
            insecureSkipHostCheck = true;
          };
          options = {
            urAccepted = -1;
            crashReportingEnabled = false;
          };
        };
      };
      systemd.services.syncthing.serviceConfig.SupplementaryGroups = ["paperless" "users" "data"];
      # mergerfs takes the caller's groups from /etc/group, not the unit's SupplementaryGroups
      users.users.${cfg.user}.extraGroups = ["data"];

      systemd.tmpfiles.rules = ["d /data/sync 0750 ${cfg.user} ${cfg.group} -"];

      systemd.services.syncthing-peers = {
        description = "Push the sops-held devices and folders into Syncthing";
        requires = ["syncthing.service"];
        after = ["syncthing.service" "syncthing-init.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = peers;
          User = cfg.user;
          Group = cfg.group;
          SupplementaryGroups = ["paperless" "data"];
          RuntimeDirectory = "syncthing-peers";
        };
      };
    };
  };
}
