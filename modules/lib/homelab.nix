# Single owner of the `den.lib.homelab` key.
#
# den.lib is declared freeform multi-writer, unlike flake-parts' flake.lib which
# is `unique raw` and can only ever be written by one module - so helpers may be
# split across files here if this one grows.
{lib, ...}: {
  den.lib.homelab = rec {
    base-domain = "nouritsu.com";
    host-ip = "192.168.178.128";
    lan-cidr = "192.168.178.0/24";
    lan-interface = "end0";

    # one provider behind both: postfix relays through it, and the services
    # that send their own mail talk to it directly
    smtp = {
      host = "smtp.hostinger.com";
      port = 465;
    };
    imap = {
      host = "imap.hostinger.com";
      port = 993;
    };

    fqdn = subdomain: "${subdomain}.${base-domain}";

    # sopsFile for the secrets two hosts must agree on
    shared-secrets = ../aspects/features/secrets/shared.yaml;

    # Put a container on gluetun's network. It can publish no ports of its own;
    # the service declares them through the `gluetun-ports` quirk and gluetun
    # publishes them on its behalf.
    #
    # mkAfter keeps this flag last, after the service's own (order 1000) and the
    # --group-add the containers aspect adds at order 1400.
    via-gluetun = name: {
      virtualisation.oci-containers.containers.${name} = {
        dependsOn = ["gluetun"];
        extraOptions = lib.mkAfter ["--network=container:gluetun"];
      };

      # down whenever gluetun is, back once it is healthy again; not upheldBy, which revives a removed service mid-switch
      systemd.services."podman-${name}" = {
        bindsTo = ["podman-gluetun.service"];
        wantedBy = ["podman-gluetun.service"];
      };
    };

    # Put containers on a podman network of their own, where they reach each
    # other by container name. Podman's published ports skip nixos-fw, so a
    # port only caddy or rathole needs is published on 127.0.0.1.
    private-network = network: names: {config, ...}: let
      podman = lib.getExe config.virtualisation.podman.package;
      unit = "podman-network-${network}";
      # pihole holds 53 on every address; netavark forwards the containers'
      # 53 to aardvark-dns here
      dns-port = 1053;
    in {
      virtualisation.containers.containersConf.settings.network.dns_bind_port = dns-port;
      networking.firewall.interfaces."podman+" = {
        allowedUDPPorts = [dns-port];
        allowedTCPPorts = [dns-port];
      };

      virtualisation.oci-containers.containers = lib.genAttrs names (_: {
        networks = [network];
      });

      systemd.services =
        {
          ${unit} = {
            description = "Podman network ${network}";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = "${podman} network exists ${network} || ${podman} network create ${network}";
          };
        }
        // lib.genAttrs (map (name: "podman-${name}") names) (_: {
          requires = ["${unit}.service"];
          after = ["${unit}.service"];
        });
    };
  };
}
