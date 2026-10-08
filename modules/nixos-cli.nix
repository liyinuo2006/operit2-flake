# 仅把 Operit2 CLI 装进系统（不运行常驻节点）。
# 适合只用命令行、或想自己写 systemd 单元的场合。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.operit2-cli;
in
{
  options.programs.operit2-cli = {
    enable = lib.mkEnableOption "Operit2 CLI（系统可见）";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/cli.nix { };
      defaultText = lib.literalExpression "operit2-cli";
      description = "Operit2 CLI 包。";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
