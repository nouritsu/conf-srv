{
  den.aspects.services.atuin = let
    # off gluetun's 8888, the module's default
    port = 8091;
  in {
    endpoint = {
      subdomain = "atuin";
      inherit port;
    };
    backup.paths = ["/var/lib/private/atuin"];

    nixos = {
      services.atuin = {
        enable = true;
        inherit port;
        openRegistration = true;
        database = {
          createLocally = false;
          uri = "sqlite:///var/lib/atuin/atuin.db";
        };
      };

      systemd.services.atuin.serviceConfig.StateDirectory = "atuin";
    };
  };
}
