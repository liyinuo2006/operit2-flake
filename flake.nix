{
  description = "Operit2（Flutter GUI + Rust CLI）的 Nix 打包：桌面应用与无界面 Link 节点（仅 x86_64-linux）";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = rec {
        operit2-desktop = pkgs.callPackage ./pkgs/desktop.nix { };
        operit2-cli = pkgs.callPackage ./pkgs/cli.nix { };
        default = operit2-desktop;
      };

      # 想注入 pkgs.operit2-desktop / pkgs.operit2-cli 的场合使用。
      overlays.default = final: _prev: {
        operit2-desktop = final.callPackage ./pkgs/desktop.nix { };
        operit2-cli = final.callPackage ./pkgs/cli.nix { };
      };

      nixosModules = {
        # 无界面 CLI Link 节点（services.operit2-link）。
        link = import ./modules/nixos-link.nix;
        # 系统级安装 GUI（programs.operit2-desktop.enable）。
        desktop = import ./modules/nixos-desktop.nix;
        default = import ./modules/nixos-link.nix;
      };

      homeModules = {
        # 用户级安装 GUI（programs.operit2-desktop.enable）。
        desktop = import ./modules/home-desktop.nix;
        default = import ./modules/home-desktop.nix;
      };

      formatter.${system} = pkgs.nixfmt;

      checks.${system} = {
        operit2-cli = pkgs.callPackage ./pkgs/cli.nix { };
        operit2-desktop = pkgs.callPackage ./pkgs/desktop.nix { };
      };
    };
}
