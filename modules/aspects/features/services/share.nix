{
  den.aspects.services.enclosed = let
    port = 8788;
  in {
    endpoint = {
      subdomain = "share";
      public = true;
      inherit port;
    };

    nixos = {config, ...}: {
      sops.secrets."enclosed/jwt-secret" = {};
      sops.secrets."enclosed/auth-users" = {};
      sops.templates."enclosed.env" = {
        content = ''
          AUTHENTICATION_JWT_SECRET=${config.sops.placeholder."enclosed/jwt-secret"}
          AUTHENTICATION_USERS=${config.sops.placeholder."enclosed/auth-users"}
        '';
      };

      virtualisation.oci-containers.containers.enclosed = {
        image = "corentinth/enclosed:latest@sha256:e65f73b085823ceeab1a39c515614c1a24e9b5c69b8e1221d3d7071a4f8bc4a8";
        ports = ["${toString port}:8787"];
        environment.PUBLIC_IS_AUTHENTICATION_REQUIRED = "true";
        environmentFiles = [config.sops.templates."enclosed.env".path];
        volumes = ["/data/enclosed:/app/.data"];
      };

      systemd.tmpfiles.rules = ["d /data/enclosed 0775 1000 data -"];
    };
  };
}
