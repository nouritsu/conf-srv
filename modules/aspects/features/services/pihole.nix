{
  den,
  inputs,
  ...
}: let
  port = 8081;
in {
  den.aspects.services.pihole = {
    endpoint = {
      subdomain = "pihole";
      inherit port;
    };

    # also the consumer: every lan endpoint gets a local A record
    nixos = {
      endpoint,
      config,
      pkgs,
      lib,
      ...
    }: let
      inherit (den.lib.homelab) fqdn host-ip lan-interface;

      TWELVE_HOURS_SECONDS = 43200;

      local =
        lib.sort (a: b: a.subdomain < b.subdomain)
        (lib.filter (e: !(e.public or false)) endpoint);
    in {
      environment.systemPackages = [pkgs.pihole-ftl];
      # NetworkManager owns end0; it does DHCP itself and forces
      # networking.useDHCP = false. Only the resolver is ours.
      networking.nameservers = ["127.0.0.1"];
      services.resolved = {
        enable = true;
        settings.Resolve = {
          DNSStubListener = "no";
          MulticastDNS = "off";
        };
      };
      services.pihole-ftl = {
        enable = true;
        openFirewallDNS = true;
        openFirewallWebserver = true;
        lists = [
          {
            url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.plus.txt";
            type = "block";
            enabled = true;
            description = "Hagezi Pro Plus";
          }
        ];
        settings = {
          dns = {
            bind_hosts = [host-ip "127.0.0.1"];
            interface = lan-interface;
            # LOCAL ignores tailnet peers, since tailscale0 is only a /32
            listeningMode = "ALL";
            upstreams = ["1.1.1.1" "1.0.0.1"];
            domainNeeded = true;
            expandHosts = true;
            # router-only names (lenovo.fritz.box) and lan reverse lookups go to the FRITZ!Box
            revServers = ["true,192.168.178.0/24,192.168.178.1,fritz.box"];
            hosts =
              [
                "192.168.178.1   gateway"
                "${host-ip}   pihole"
              ]
              ++ map (e: "${host-ip}   ${fqdn e.subdomain}") local;
          };
          dhcp.active = false;
          webserver.session.timeout = TWELVE_HOURS_SECONDS;
          ntp = {
            ipv4.active = false;
            ipv6.active = false;
            sync.active = false;
          };
        };
      };
      services.pihole-web = {
        enable = true;
        ports = [port];
      };

      sops.secrets."pihole/password" = {};
      # an FTLCONF_ setting is read-only in the web ui; ftl hashes the password itself
      sops.templates."pihole.env" = {
        content = ''
          FTLCONF_webserver_api_password=${config.sops.placeholder."pihole/password"}
        '';
        restartUnits = ["pihole-ftl.service"];
      };
      systemd.services.pihole-ftl.serviceConfig.EnvironmentFile = config.sops.templates."pihole.env".path;

      systemd.services.pihole-ftl-setup = {
        # unstable's setup script tolerates already-present lists; drop once nixos-raspberrypi's nixpkgs has it
        script = lib.mkForce (
          import "${inputs.nixpkgs}/nixos/modules/services/networking/pihole-ftl-setup-script.nix" {
            cfg = config.services.pihole-ftl;
            inherit config lib pkgs;
          }
        );

        # a freshly restarted ftl answers the api before it can write gravity.db
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "5s";
        };
        startLimitBurst = 3;
        startLimitIntervalSec = 120;
      };
    };
  };
}
