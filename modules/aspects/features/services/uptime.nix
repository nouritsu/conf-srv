{den, ...}: let
  inherit (den.lib.policy) pipe;
  port = 4000;
in {
  # every other live host's public endpoints are collected here
  den.policies.collect-remote-endpoints = {host, ...}: let
    self = host.name;
  in [
    (pipe.from "endpoint" [
      # stages run in order: drop this host's own endpoints, then collect
      (pipe.filter (_: false))
      (pipe.collectAll ({host, ...}: host.name != self && host.active && host.deploy != null))
      (pipe.filter (e: e.public or false))
      (pipe.as "remote-endpoint")
    ])
  ];

  # consumes the `endpoint` and `remote-endpoint` quirks: every vhost they name is checked through caddy
  den.aspects.services.gatus = {
    includes = [den.policies.collect-remote-endpoints];

    endpoint = {
      subdomain = "uptime";
      inherit port;
    };
    backup.paths = ["/var/lib/private/gatus"];

    nixos = {
      endpoint,
      remote-endpoint,
      lib,
      ...
    }: let
      inherit (den.lib.homelab) fqdn;
      public = e: e.public or false;

      check = e: {
        name = e.subdomain or e.domain;
        group =
          if public e
          then "public"
          else "lan";
        url = "https://${e.domain or (fqdn e.subdomain)}";
        # a refused connection leaves [STATUS] at 0
        conditions = ["[CONNECTED] == true" "[STATUS] < 500"];
      };
    in {
      services.gatus = {
        enable = true;
        settings = {
          web = {
            address = "127.0.0.1";
            inherit port;
          };
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
          };
          # a vhost-less endpoint is only reached through another's vhost
          endpoints = lib.unique (map check (lib.filter (e: e.vhost or true) (endpoint ++ remote-endpoint)));
        };
      };
    };
  };
}
