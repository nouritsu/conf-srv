# conf-nixos' starship, wrapped here from the host's pkgs
{inputs, ...}: {
  den.aspects.apps.starship.nixos = {
    pkgs,
    lib,
    ...
  }: let
    starship = inputs.wrappers.wrappers.starship.wrap [
      {
        inherit pkgs;
        package = pkgs.starship;
      }

      inputs.conf-nixos.nixosModules.wstarship-settings
      inputs.conf-nixos.nixosModules.wstarship-theme

      # host stats, time and battery, picked by fish over ssh
      ({config, ...}: {
        # default only, so the STARSHIP_CONFIG fish exports wins
        env.STARSHIP_CONFIG = lib.mkForce null;
        envDefault.STARSHIP_CONFIG = config.constructFiles."starship.toml".path;

        constructFiles."starship-ssh.toml" = {
          relPath = "starship-ssh.toml";
          content = builtins.toJSON (lib.recursiveUpdate config.settings {
            custom.cpu.disabled = false;
            memory_usage.disabled = false;
            custom.load.disabled = false;
            time.disabled = false;
            battery.disabled = false;
          });
          builder = ''${pkgs.remarshal}/bin/json2toml "$1" "$2"'';
        };
      })
    ];

    settings = starship.configuration.constructFiles."starship.toml".outPath;
    sshSettings = starship.configuration.constructFiles."starship-ssh.toml".outPath;
  in {
    environment.systemPackages = [starship];

    # the prompt runs the wrapper, which only defaults STARSHIP_CONFIG
    programs.fish.interactiveShellInit = ''
      if test "$TERM" != dumb
        if set -q SSH_CONNECTION
          set -gx STARSHIP_CONFIG ${sshSettings}
        else
          set -gx STARSHIP_CONFIG ${settings}
        end

        function starship_transient_prompt_func
          ${lib.getExe starship} module character
        end

        ${lib.getExe starship} init fish | source
        enable_transience
      end
    '';
  };
}
