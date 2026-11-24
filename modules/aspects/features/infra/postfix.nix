{den, ...}: {
  den.aspects.postfix.nixos = {
    config,
    pkgs,
    ...
  }: let
    inherit (den.lib.homelab) base-domain smtp;
    relay = "[${smtp.host}]:${toString smtp.port}";
    address = config.sops.placeholder."mail/address";
  in {
    sops.secrets."mail/address" = {};
    sops.secrets."mail/token" = {};
    sops.templates."mail-sasl-password" = {
      content = "${relay} ${address}:${config.sops.placeholder."mail/token"}";
    };
    # proton only relays mail sent as the address the token belongs to
    sops.templates."mail-sender" = {
      content = "/.+/ ${address}";
    };

    services.postfix = {
      enable = true;
      settings.main = {
        mydomain = base-domain;
        myorigin = base-domain;
        mydestination = [];
        mynetworks = ["127.0.0.0/8" "[::1]/128"];
        relayhost = [relay];
        sender_canonical_maps = "regexp:${config.sops.templates."mail-sender".path}";
        smtp_tls_security_level = "secure";
        smtp_sasl_auth_enable = "yes";
        smtp_sasl_password_maps = "texthash:${config.sops.templates."mail-sasl-password".path}";
        smtp_sasl_security_options = "noanonymous";
        inet_interfaces = "loopback-only";
      };
    };

    environment.systemPackages = [pkgs.mailutils];
  };
}
