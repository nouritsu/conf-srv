# Quirks are den's mechanism for one aspect emitting structured data that other
# aspects aggregate, without either side knowing the other exists. A service
# declares what it needs; caddy, pihole, rathole, gluetun and gatus each read the
# whole pool and build their own config from it.
{
  den.quirks.endpoint.description = ''
    A service reachable through caddy. { subdomain | domain, port ?, extraConfig ?, public ? false, vhost ? true } -
    public is for the internet, else the lan only. A host with tunnels-via
    sends its public endpoints through the tunnel; any other serves them itself.
    vhost = false tunnels a public port without a site of its own, for
    another vhost on the tunnel's server to proxy to.
  '';

  den.quirks.tunnel.description = ''
    Another host's public endpoints, collected onto the host whose rathole
    server and caddy publish them. Same shape as `endpoint`.
  '';

  den.quirks.remote-endpoint.description = ''
    Every other live host's public endpoints, collected onto the host whose
    gatus checks them. Same shape as `endpoint`.
  '';

  den.quirks.gluetun-ports.description = ''
    Host port mappings a service needs published on its behalf, because it
    shares gluetun's network namespace and can publish none of its own.
  '';

  den.quirks.backup.description = ''
    State a service needs backed up. { paths ? [], exclude ? [] } - real
    directories, not the /var/lib/<name> symlinks DynamicUser leaves behind.
  '';
}
