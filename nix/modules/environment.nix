{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  inherit (lib) types;
  cfg = config.environment;

  exportedEnvVars =
    let
      absoluteVariables = lib.mapAttrs (n: lib.toList) cfg.variables;

      suffixedVariables = lib.flip lib.mapAttrs cfg.profileRelativeEnvVars (
        envVar: listSuffixes:
        lib.concatMap (profile: map (suffix: "${profile}${suffix}") listSuffixes) cfg.profiles
      );

      allVariables = lib.zipAttrsWith (n: lib.concatLists) [
        absoluteVariables
        suffixedVariables
      ];

      exportVariables = lib.mapAttrsToList (
        n: v:
        ''export ${n}="${lib.concatStringsSep ":" v}${
          lib.optionalString (v != [ ] && suffixedVariables ? ${n}) "\${${n}:+:}"
        }${lib.optionalString (suffixedVariables ? ${n}) "\${${n}:-}"}"''
      ) allVariables;
    in
    lib.concatStringsSep "\n" exportVariables;

  pathDir = "/run/system-manager/sw";
in
{
  options.environment = {
    # !!! isn't there a better way?
    extraInit = lib.mkOption {
      default = "";
      description = ''
        Shell script code called during global environment initialisation
        after all variables and profileVariables have been set.
        This code is assumed to be shell-independent, which means you should
        stick to pure sh without sh word split.
      '';
      type = types.lines;
    };

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

    profileRelativeEnvVars = lib.mkOption {
      type = types.attrsOf (types.listOf types.str);
      example = {
        PATH = [ "/bin" ];
        MANPATH = [
          "/man"
          "/share/man"
        ];
      };
      description = ''
        Attribute set of environment variable.  Each attribute maps to a list
        of relative paths.  Each relative path is appended to the each profile
        of {option}`environment.profiles` to form the content of the
        corresponding environment variable.
      '';
    };

    profileRelativeSessionVariables = lib.mkOption {
      type = types.attrsOf (types.listOf types.str);
      example = {
        PATH = [ "/bin" ];
        MANPATH = [
          "/man"
          "/share/man"
        ];
      };
      description = ''
        Attribute set of environment variable used in the global
        environment. These variables will be set by PAM early in the
        login process.

        Variable substitution is available as described in
        {manpage}`pam_env.conf(5)`.

        Each attribute maps to a list of relative paths. Each relative
        path is appended to the each profile of
        {option}`environment.profiles` to form the content of
        the corresponding environment variable.

        Also, these variables are merged into
        [](#opt-environment.profileRelativeEnvVars) and it is
        therefore not possible to use PAM style variables such as
        `@{HOME}`.
      '';
    };

    profiles = lib.mkOption {
      default = [ ];
      description = ''
        A list of profiles used to setup the global environment.
      '';
      type = types.listOf types.str;
    };

    sessionVariables = lib.mkOption {
      default = { };
      description = ''
        A set of environment variables used in the global environment.
        These variables will be set by PAM early in the login process.

        The value of each session variable can be either a string or a
        list of strings. The latter is concatenated, interspersed with
        colon characters.

        Note, due to limitations in the PAM format values may not
        contain the `"` character.

        Also, these variables are merged into
        [](#opt-environment.variables) and it is
        therefore not possible to use PAM style variables such as
        `@{HOME}`.
      '';
      inherit (options.environment.variables) type apply;
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

    variables = lib.mkOption {
      default = { };
      example = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
      description = ''
        A set of environment variables used in the global environment.
        These variables will be set on shell initialisation (e.g. in /etc/profile).
        The value of each variable can be either a string or a list of
        strings.  The latter is concatenated, interspersed with colon
        characters.
      '';
      type = types.attrsOf (
        types.oneOf [
          (types.listOf (
            types.oneOf [
              types.int
              types.str
              types.path
            ]
          ))
          types.int
          types.str
          types.path
        ]
      );
      apply =
        let
          toStr = v: if lib.isPath v then "${v}" else toString v;
        in
        lib.mapAttrs (n: v: if lib.isList v then lib.concatMapStringsSep ":" toStr v else toStr v);
    };
  };

  config = {
    environment = {
      etc = {
        # TODO: figure out how to properly add fish support. We could start by
        # looking at what NixOS and HM do to set up the fish env.
        #"fish/conf.d/system-manager-path.fish".text = ''
        #  set -gx PATH "${pathDir}/bin/" $PATH
        #'';
        #"fish/conf.d/system-manager-path.fish".executable = true;

        "profile.d/system-manager-set-environment.sh".text = ''
          if [ -z "$__SYSTEM_MANAGER_SET_ENVIRONMENT_DONE" ]; then
              . ${lib.escapeShellArg config.environment.etc."system-manager-set-environment.sh".source}
          fi
        '';

        "system-manager-set-environment.sh".text = ''
          # DO NOT EDIT -- this file has been generated automatically.

          # Prevent this file from being sourced by child shells.
          export __SYSTEM_MANAGER_SET_ENVIRONMENT_DONE=1

          ${exportedEnvVars}

          ${cfg.extraInit}
        '';
      };

      pathsToLink = [
        "/bin"
      ];

      profiles = lib.mkAfter [
        pathDir
      ];

      profileRelativeEnvVars = cfg.profileRelativeSessionVariables;

      profileRelativeSessionVariables = {
        PATH = [ "/bin" ];
        INFOPATH = [
          "/info"
          "/share/info"
        ];
        QTWEBKIT_PLUGIN_PATH = [ "/lib/mozilla/plugins/" ];
        GTK_PATH = [
          "/lib/gtk-2.0"
          "/lib/gtk-3.0"
          "/lib/gtk-4.0"
        ];
        # XDG_CONFIG_DIRS = [ "/etc/xdg" ];
        # XDG_DATA_DIRS = [ "/share" ];
        LIBEXEC_PATH = [ "/libexec" ];
      };

      # Set session variables in the shell as well. This is usually
      # unnecessary, but it allows changes to session variables to take
      # effect without restarting the session (e.g. by opening a new
      # terminal instead of logging out of X11).
      variables = cfg.sessionVariables;
    };

    systemd.services.system-manager-path = {
      enable = true;
      after = [
        "system-manager-pre.target"
        "systemd-journald.service"
      ];
      before = [
        "shutdown.target"
        "system-manager.target"
        "systemd-tmpfiles-clean.service"
        "systemd-tmpfiles-setup.service"
      ];
      conflicts = [ "shutdown.target" ];
      description = "Create system-manager files and directories";
      unitConfig.DefaultDependencies = false;
      unitConfig.PropagatesStopTo = [ "system-manager.target" ];
      unitConfig.RequiresMountsFor = [ "/nix/store" ];
      unitConfig.WantsMountsFor = [ pathDir ];
      requiredBy = [ "system-manager.target" ];
      serviceConfig.RemainAfterExit = true;
      serviceConfig.RestartMode = "direct";
      serviceConfig.Type = "oneshot";
      wants = [ "system-manager-pre.target" ];
      script =
        let
          pathDrv = pkgs.buildEnv {
            name = "system-manager-path";
            paths = cfg.systemPackages;
            inherit (cfg) extraOutputsToInstall pathsToLink;
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
