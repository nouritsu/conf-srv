# A second host that selects every service aspect, including the ones the real
# homelab does not run. Without it those aspects are never type-checked: den
# only evaluates what a host selects, so a broken deselected service would stay
# invisible until the day it is switched on.
#
# services._ is den's own aggregate over the namespace - it expands to every
# immediate child of den.aspects.services - so a service is covered here from
# the moment it is defined, with no list to remember to update.
#
#   nix eval .#nixosConfigurations.check-all.config.system.build.toplevel.drvPath
{den, ...}: {
  den.aspects.check-all.includes = with den.aspects; [
    homelab
    services._
  ];

  # the same for games, on x86 where their images run; caddy is for valheim-files
  den.aspects.check-games.includes = with den.aspects; [
    nenya
    caddy
    games._
  ];
}
