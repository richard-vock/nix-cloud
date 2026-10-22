{ config, lib, pkgs, ... }:
let
  cfg = config.services.cooklang;
  stateDir = "/var/lib/cooklang";
  recipesDir = "${stateDir}/recipes";
  args = [
    "server"
    "--host"
    cfg.listenAddress
    "--port"
    (toString cfg.port)
    recipesDir
  ];
in
{
  options.services.cooklang = {
    enable = lib.mkEnableOption "the Cooklang recipe web server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cook-cli;
      defaultText = lib.literalExpression "pkgs.cook-cli";
      description = "CookCLI package providing the cook server command.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Listen address. No login is configured by this module; prefer loopback behind an access-controlled proxy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9080;
      description = "HTTP listen port. No firewall ports are opened by this module.";
    };

  };

  config = lib.mkIf cfg.enable {
    users.groups.cooklang = { };
    users.users.cooklang = {
      isSystemUser = true;
      group = "cooklang";
      home = stateDir;
      description = "Cooklang recipe server";
    };

    systemd.services.cooklang = {
      description = "Cooklang recipe server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        HOME = stateDir;
        XDG_CONFIG_HOME = "${stateDir}/.config";
        XDG_CACHE_HOME = "${stateDir}/.cache";
        XDG_DATA_HOME = "${stateDir}/.local/share";
      };
      preStart = ''
        ${pkgs.coreutils}/bin/install -d -m 0750 ${recipesDir}
      '';
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} ${lib.escapeShellArgs args}";
        User = "cooklang";
        Group = "cooklang";
        StateDirectory = "cooklang";
        StateDirectoryMode = "0750";
        WorkingDirectory = stateDir;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        CapabilityBoundingSet = "";
      };
    };
  };
}
