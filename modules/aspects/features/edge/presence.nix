{den, ...}: {
  # my status for the website's frame, from the homelab through its rathole tunnel, at
  # nouritsu.com/status.json; the homelab serves that one file and nothing else
  den.aspects.edge.presence.nixos = {
    tunnel,
    lib,
    ...
  }: let
    feed =
      lib.findSingle (e: e.subdomain == "presence")
      (throw "edge.presence: no host tunnels a presence endpoint here")
      (throw "edge.presence: more than one presence tunnel")
      tunnel;
  in {
    # edge.www's endpoint owns the domain; a second endpoint would claim it again
    services.caddy.virtualHosts.${den.lib.homelab.base-domain}.extraConfig = ''
      handle /status.json {
        reverse_proxy localhost:${toString feed.port}
      }
    '';
  };
}
