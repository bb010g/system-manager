{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) types;
  cfg = config.environment;
  pathDir = "/run/system-manager/sw";
in
{
  options.environment = {
    extraOutputsToInstall = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "doc"
        "info"
        "devdoc"
      ];
      description = ''
        Entries listed here will be appended to the `meta.outputsToInstall` attribute for each package in `environment.systemPackages`, and the files from the corresponding derivation outputs symlinked into {file}`/run/system-manager/sw`.

        For example, this can be used to install the `dev` and `info` outputs for all packages in the system environment, if they are available.

        To use specific outputs instead of configuring them globally, select the corresponding attribute on the package derivation, e.g. `libxml2.dev` or `coreutils.info`.
      '';
    };

    pathsToLink = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        The list of directories to appear in {file}`/run/system-manager/sw`.
      '';
    };

    systemPackages = lib.mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.firefox pkgs.thunderbird ]";
      description = ''
        The set of packages that appear in {file}`/run/system-manager/sw`.
        These packages are automatically available to all users,
        and are automatically updated every time you rebuild the system configuration.
        (The latter is the main difference with installing them in the default profile,
        {file}`/nix/var/nix/profiles/default`.)
      '';
    };
  };

  config = {
    environment = {
      pathsToLink = [
        "/bin"
      ];

      etc = {
        # TODO: figure out how to properly add fish support. We could start by
        # looking at what NixOS and HM do to set up the fish env.
        #"fish/conf.d/system-manager-path.fish".text = ''
        #  set -gx PATH "${pathDir}/bin/" $PATH
        #'';
        #"fish/conf.d/system-manager-path.fish".executable = true;

        "profile.d/system-manager-path.sh".text = ''
          export PATH=${pathDir}/bin/:''${PATH}
        '';
      };
    };

    systemd.services.system-manager-path = {
      enable = true;
      description = "";
      wantedBy = [ "system-manager.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        let
          pathDrv = pkgs.buildEnv {
            name = "system-manager-path";
            paths = config.environment.systemPackages;
            inherit (config.environment) extraOutputsToInstall pathsToLink;
          };
        in
        ''
          mkdir --parents $(dirname "${pathDir}")
          if [ -L "${pathDir}" ]; then
            unlink "${pathDir}"
          fi
          ln --symbolic --force "${pathDrv}" "${pathDir}"
        '';
    };
  };
}
