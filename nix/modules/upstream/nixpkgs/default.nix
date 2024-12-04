{
  lib,
  modulesPaths,
  pkgs,
  ...
}:
let
  inherit (lib) types;
in
{
  imports =
    [
      ./nginx.nix
    ]
    ++
    # List of imported NixOS modules
    # TODO: how will we manage this in the long term?
    map (path: modulesPaths.nixos + path) [
      "/misc/meta.nix"
      "/security/acme"
      "/security/wrappers"
      "/services/web-servers/nginx"
    ];

  options =
    # We need to ignore a bunch of options that are used in NixOS modules but
    # that don't apply to system-manager configs.
    # TODO: can we print an informational message for things like kernel modules
    # to inform users that they need to be enabled in the host system?
    {
      boot = lib.mkOption {
        type = types.raw;
      };
      security.apparmor = {
        includes = lib.mkOption {
          type = types.attrsOf types.lines;
          default = { };
          internal = true;
          apply = lib.mapAttrs pkgs.writeText;
        };
      };
    };

}
