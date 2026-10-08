# Operit2 无界面 CLI 节点：常驻 `operit2 cli link listen`，作为 Space 中的一个 CoreNode
# 接收配对、同步与多跳转发。它不是中心服务器；权限仅为本服务用户的系统权限。
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.operit2-link;
  user = "operit2-link";
  stateDir = "/var/lib/operit2-link";

  # 运行环境必须与 operit2 的存储约定一致：
  # 运行时数据位于 $XDG_DATA_HOME/operit2，CLI 配置位于 $OPERIT_CLI_CONFIG_DIR。
  runtimeEnv = {
    HOME = stateDir;
    XDG_DATA_HOME = "${stateDir}/data";
    OPERIT_CLI_CONFIG_DIR = "${stateDir}/config";
  };
  envArgs = lib.mapAttrsToList (name: value: "${name}=${value}") runtimeEnv;

  listenArgs = lib.concatStringsSep " " (
    [
      "cli"
      "link"
      "listen"
      (lib.concatStringsSep "," cfg.transports)
      "--bind"
      "${cfg.bindAddress}:${toString cfg.port}"
      "--fixed-port"
    ]
    ++ lib.optional (!cfg.discovery) "--no-discovery"
  );
in
{
  options.services.operit2-link = {
    enable = lib.mkEnableOption "Operit2 CLI Link 无界面节点";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../pkgs/cli.nix { };
      defaultText = lib.literalExpression "operit2-cli";
      description = "提供 operit2 CLI 的包。";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "监听地址。实际可达范围由 openFirewallOn / openFirewallPublic 决定。";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 37195;
      description = "Link 监听端口（固定端口，便于防火墙规则与配对地址稳定）。";
    };

    transports = lib.mkOption {
      type = lib.types.nonEmptyListOf (
        lib.types.enum [
          "tcp"
          "http"
          "ws"
        ]
      );
      default = [ "tcp" ];
      description = "Link 传输。TCP 不能与 http/ws 共用同一端口。";
    };

    discovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否开启 mDNS 局域网发现。服务器默认关闭，避免在公网网卡广播。";
    };

    openFirewallOn = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "wg0" ];
      description = "只在这些网卡上放行 Link 端口。";
    };

    openFirewallPublic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "是否在所有网卡放行 Link 端口（直接暴露公网时才需要）。";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      home = stateDir;
      description = "Operit2 Link node";
    };
    users.groups.${user} = { };

    systemd.services.operit2-link = {
      description = "Operit2 CLI Link node";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = runtimeEnv;

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = user;
        ExecStart = "${cfg.package}/bin/operit2 ${listenArgs}";
        # listen 只在收到 Ctrl-C（SIGINT）时执行 stopListening；systemd 默认发 SIGTERM。
        KillSignal = "SIGINT";
        StateDirectory = "operit2-link";
        StateDirectoryMode = "0700";
        WorkingDirectory = stateDir;
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        # AF_NETLINK 供 `ip route` 读取设备网络信息，缺少会让设备信息失败。
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = lib.optional cfg.openFirewallPublic cfg.port;
      interfaces = lib.genAttrs cfg.openFirewallOn (_: {
        allowedTCPPorts = [ cfg.port ];
      });
    };

    # 管理命令：以服务用户身份访问同一份数据目录（需要 root）。
    # 同一数据目录同时只应有一个运行中的 Core；执行配对类命令前先 `systemctl stop operit2-link`。
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "operit2-link-cli" ''
        exec ${pkgs.util-linux}/bin/runuser -u ${user} -- ${pkgs.coreutils}/bin/env ${lib.escapeShellArgs envArgs} ${cfg.package}/bin/operit2 cli "$@"
      '')
    ];
  };
}
