# 系统级安装 Operit2 桌面 GUI（所有用户可见）。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.operit2-desktop;
in
{
  options.programs.operit2-desktop = {
    enable = lib.mkEnableOption "Operit2 桌面应用（系统级安装）";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/desktop.nix { };
      defaultText = lib.literalExpression "operit2-desktop";
      description = "Operit2 桌面包。";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
