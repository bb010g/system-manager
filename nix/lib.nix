{
  nixpkgs ? <nixpkgs>,
  lib ? import (nixpkgs + "/lib"),
  nixos ? nixpkgs + "/nixos",
}:
let
  inherit (builtins) map throw toString;
  _file = ./lib.nix;
  self = {
    # Function that can be used when defining inline modules to get better location
    # reporting in module-system errors.
    # Usage example:
    #   { _file = "${printAttrPos (builtins.unsafeGetAttrPos "a" { a = null; })}: inline module"; }
    printAttrPos =
      {
        file,
        line,
        column,
      }:
      "${file}:${toString line}:${toString column}";

    makeSystemConfig =
      makeSystemConfigArgs@{
        modules,
        extraSpecialArgs ? { },
        pkgs ? null,
      }:
      let
        # Module that sets additional module arguments
        extraArgsModule =
          {
            config,
            lib,
            modulesPaths,
            pkgs,
            ...
          }:
          {
            inherit _file;
            key = "${modulesPaths.system-manager}:extraArgsModule";
            _module.args = {
              pkgs =
                if makeSystemConfigArgs.pkgs or null != null then
                  makeSystemConfigArgs.pkgs
                else
                  import nixpkgs {
                    system = config.nixpkgs.hostPlatform;
                    inherit (config.nixpkgs) config;
                  };
              utils = import (nixos + "/lib/utils.nix") {
                inherit lib config pkgs;
              };
              # Pass the wrapped system-manager binary down
              # TODO: Use nixpkgs version by default.
              inherit (import ../packages.nix { inherit pkgs; })
                system-manager
                ;
            };
          };

        # Module that imports the default module.
        # Necessary to use `modulesPaths.system-manager`.
        defaultModule =
          { modulesPaths, ... }:
          {
            inherit _file;
            key = "${modulesPaths.system-manager}:defaultModule";
            imports = [ (modulesPaths.system-manager + "/default.nix") ];
          };

        modulesPaths = {
          nixos = toString (nixos + "/modules");
          system-manager = toString ./modules;
        } // extraSpecialArgs.modulesPaths or { };

        evaluation = lib.evalModules {
          specialArgs = extraSpecialArgs // {
            inherit modulesPaths;
            ${
              lib.warnIf (extraSpecialArgs ? modulesPath)
                "makeSystemConfig: Special argument `modulesPath` is unsupported. Using provided `specialArgs.modulesPath` anyways."
                "modulesPath"
            } =
              extraSpecialArgs.modulesPath
                or (throw "makeSystemConfig: Special argument `modulesPath` is unsupported. Please use `modulesPaths.nixos` or `modulesPaths.system-manager` instead.");
            ${
              lib.warnIf (extraSpecialArgs ? nixosModulesPath)
                "makeSystemConfig: Special argument `nixosModulesPath` is unsupported. Using `specialArgs.nixosModulesPath` anyways."
                "nixosModulesPath"
            } =
              extraSpecialArgs.nixosModulesPath
                or (throw "makeSystemConfig: Special argument `nixosModulesPath` has been removed. Please use `modulesPaths.nixos` instead.");
          };
          modules = [
            extraArgsModule
            defaultModule
          ] ++ modules;
        };

        inherit (evaluation) config;
        inherit (config.nixpkgs) pkgs;

        returnIfNoAssertions =
          drv:
          let
            failedAssertions = map (x: x.message) (lib.filter (x: !x.assertion) config.assertions);
          in
          if failedAssertions != [ ] then
            throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
          else
            lib.showWarnings config.warnings drv;

        servicesPath = pkgs.writeTextFile {
          name = "services";
          destination = "/services.json";
          text = lib.generators.toJSON { } config.build.services;
        };

        etcPath = pkgs.writeTextFile {
          name = "etcFiles";
          destination = "/etcFiles.json";
          text = lib.generators.toJSON { } { inherit (config.build.etc) entries staticEnv; };
        };

        linkFarmNestedEntryFromDrv = dirs: drv: {
          name = lib.concatStringsSep "/" (dirs ++ [ "${drv.name}" ]);
          path = drv;
        };
        linkFarmEntryFromDrv = linkFarmNestedEntryFromDrv [ ];
        linkFarmBinEntryFromDrv = linkFarmNestedEntryFromDrv [ "bin" ];

        toplevel =
          let
            scripts = lib.mapAttrsToList (_: script: linkFarmBinEntryFromDrv script) config.build.scripts;

            entries = [
              (linkFarmEntryFromDrv servicesPath)
              (linkFarmEntryFromDrv etcPath)
            ] ++ scripts;

            attrsOverlays.addPassthru = finalAttrs: prevAttrs: {
              passthru = (prevAttrs.passthru or { }) // {
                inherit config evaluation;
              };
            };

            attrsOverlays.addPassedChecks =
              finalAttrs: prevAttrs:
              let
                inherit (finalAttrs.passthru.evaluation) config;
                prevPassedChecks = prevAttrs.passedChecks or "";
              in
              {
                passedChecks = lib.concatStringsSep " " (
                  lib.optionals (prevPassedChecks != "") prevPassedChecks ++ config.system.checks
                );
              };

            attrsOverlay = lib.composeManyExtensions [
              attrsOverlays.addPassthru
              attrsOverlays.addPassedChecks
            ];
          in
          (pkgs.linkFarm "system-manager" entries).overrideAttrs attrsOverlay;
      in
      returnIfNoAssertions toplevel;

    mkTestPreamble =
      {
        node,
        profile,
        action,
      }:
      ''
        ${node}.succeed("${profile}/bin/${action} 2>&1 | tee /tmp/output.log")
        ${node}.succeed("! grep -F 'ERROR' /tmp/output.log")
      '';

    activateProfileSnippet =
      { node, profile }:
      self.mkTestPreamble {
        inherit node profile;
        action = "activate";
      };
    deactivateProfileSnippet =
      { node, profile }:
      self.mkTestPreamble {
        inherit node profile;
        action = "deactivate";
      };
    prepopulateProfileSnippet =
      { node, profile }:
      self.mkTestPreamble {
        inherit node profile;
        action = "prepopulate";
      };
  };
in
self
