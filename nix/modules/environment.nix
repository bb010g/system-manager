{
  config,
  lib,
  options,
  pkgs,
  ...
}:

let
  cfg = config.environment;

  exportedEnvVars =
    let
      absoluteVariables =
        lib.mapAttrs (n: lib.toList) cfg.variables;

      suffixedVariables =
        lib.flip lib.mapAttrs cfg.profileRelativeEnvVars (envVar: listSuffixes:
          lib.concatMap (profile: map (suffix: "${profile}${suffix}") listSuffixes) cfg.profiles
        );

      allVariables =
        lib.zipAttrsWith (n: lib.concatLists) [ absoluteVariables suffixedVariables ];

      exportVariables =
        lib.mapAttrsToList (n: v: ''export ${n}="${lib.concatStringsSep ":" v}${lib.optionalString (v != [ ] && suffixedVariables ? ${n}) "\${${n}:+:}"}${lib.optionalString (suffixedVariables ? ${n}) "\${${n}:-}"}"'') allVariables;
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
      type = lib.types.lines;
    };

    pathsToLink = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    profileRelativeEnvVars = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      example = { PATH = [ "/bin" ]; MANPATH = [ "/man" "/share/man" ]; };
      description = ''
        Attribute set of environment variable.  Each attribute maps to a list
        of relative paths.  Each relative path is appended to the each profile
        of {option}`environment.profiles` to form the content of the
        corresponding environment variable.
      '';
    };

    profileRelativeSessionVariables = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      example = { PATH = [ "/bin" ]; MANPATH = [ "/man" "/share/man" ]; };
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
      default = [];
      description = ''
        A list of profiles used to setup the global environment.
      '';
      type = lib.types.listOf lib.types.str;
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
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };

    variables = lib.mkOption {
      default = {};
      example = { EDITOR = "nvim"; VISUAL = "nvim"; };
      description = ''
        A set of environment variables used in the global environment.
        These variables will be set on shell initialisation (e.g. in /etc/profile).
        The value of each variable can be either a string or a list of
        strings.  The latter is concatenated, interspersed with colon
        characters.
      '';
      type = let
        t = lib.types;
      in t.attrsOf (t.oneOf [ (t.listOf (t.oneOf [ t.int t.str t.path ])) t.int t.str t.path ]);
      apply = let
        toStr = v: if lib.isPath v then "${v}" else toString v;
      in lib.mapAttrs (n: v: if lib.isList v then lib.concatMapStringsSep ":" toStr v else toStr v);
    };
  };

  config = {
    environment = {
      etc = {
        # TODO: figure out how to properly add fish support. We could start by
        # looking at what NixOS and HM do to set up the fish env.
        #"fish/conf.d/system-manager-path.fish".source =
        #  pkgs.writeTextFile {
        #    name = "system-manager-path.fish";
        #    executable = true;
        #    text = ''
        #      set -gx PATH "${pathDir}/bin/" $PATH
        #    '';
        #  };

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
        INFOPATH = [ "/info" "/share/info" ];
        QTWEBKIT_PLUGIN_PATH = [ "/lib/mozilla/plugins/" ];
        GTK_PATH = [ "/lib/gtk-2.0" "/lib/gtk-3.0" "/lib/gtk-4.0" ];
        XDG_CONFIG_DIRS = [ "/etc/xdg" ];
        XDG_DATA_DIRS = [ "/share" ];
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
            paths = cfg.systemPackages;
            inherit (cfg) pathsToLink;
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
