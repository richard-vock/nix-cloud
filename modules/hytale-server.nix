{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.hytale-server;

  serverArgs = [
    "--assets"
    "Assets.zip"
    "--bind"
    cfg.bind
  ]
  ++ optionals cfg.backup.enable [
    "--backup"
    "--backup-dir"
    "backups"
    "--backup-frequency"
    (toString cfg.backup.frequency)
    "--backup-max-count"
    (toString cfg.backup.maxCount)
  ]
  ++ cfg.extraArgs;

  # Share startup preparation and arguments between systemd and the console.
  startServer = pkgs.writeShellScript "hytale-start-server" ''
    set -eu
    cd ${escapeShellArg (toString cfg.dataDir)}
    ${pkgs.coreutils}/bin/ln -sf ${escapeShellArg (toString cfg.serverJar)} HytaleServer.jar
    ${pkgs.coreutils}/bin/ln -sf ${escapeShellArg (toString cfg.assetsZip)} Assets.zip

    aotFile="$(${pkgs.coreutils}/bin/dirname ${escapeShellArg (toString cfg.serverJar)})/HytaleServer.aot"
    if [ -f "$aotFile" ]; then
      ${pkgs.coreutils}/bin/ln -sf "$aotFile" HytaleServer.aot
    fi

    exec ${cfg.package}/bin/java ${cfg.jvmOpts} --enable-native-access=ALL-UNNAMED -jar HytaleServer.jar ${escapeShellArgs serverArgs}
  '';
in
{
  options = {
    services.hytale-server = {
      enable = mkEnableOption "Hytale dedicated game server";

      package = mkOption {
        type = types.package;
        default = pkgs.jdk25_headless;
        defaultText = literalExpression "pkgs.jdk25_headless";
        description = "Java package to use (Hytale requires Java 25+).";
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/hytale-server";
        description = "Directory for server files, world data, and backups.";
      };

      serverJar = mkOption {
        type = types.path;
        description = "Path to HytaleServer.jar.";
        example = "/home/user/hytale/Server/HytaleServer.jar";
      };

      assetsZip = mkOption {
        type = types.path;
        description = "Path to Assets.zip.";
        example = "/home/user/hytale/Assets.zip";
      };

      bind = mkOption {
        type = types.str;
        default = "0.0.0.0:5520";
        description = "Address and port to bind to.";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to open UDP port in the firewall.";
      };

      backup = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable periodic world backups.";
        };

        frequency = mkOption {
          type = types.int;
          default = 30;
          description = "Backup interval in minutes.";
        };

        maxCount = mkOption {
          type = types.int;
          default = 5;
          description = "Maximum number of backups to retain.";
        };
      };

      jvmOpts = mkOption {
        type = types.separatedString " ";
        default = "-Xms4G -Xmx4G";
        description = "JVM options (memory, GC, etc).";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra command-line arguments passed to HytaleServer.jar.";
        example = [
          "--transport"
          "TCP"
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.hytale = {
      isSystemUser = true;
      group = "hytale";
      home = cfg.dataDir;
      createHome = true;
      description = "Hytale server user";
    };

    users.groups.hytale = { };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "hytale-run-server" ''
        set -eu
        if [ "$EUID" -ne 0 ]; then
          echo "Run this command as root: sudo hytale-run-server" >&2
          exit 1
        fi
        if [ ! -t 0 ] || [ ! -t 1 ]; then
          echo "An interactive terminal is required (use ssh -t or tmux)." >&2
          exit 1
        fi

        state=$(${pkgs.systemd}/bin/systemctl show --property=ActiveState --value hytale-server.service)
        case "$state" in
          inactive|failed) ;;
          *)
            echo "Stop the service first: sudo systemctl stop hytale-server" >&2
            exit 1
            ;;
        esac

        # Preserve the terminal, but create files and credentials as the service user.
        exec ${pkgs.util-linux}/bin/runuser -u hytale -- ${startServer}
      '')
    ];

    systemd.services.hytale-server = {
      description = "Hytale Dedicated Server";

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        User = "hytale";
        Group = "hytale";
        WorkingDirectory = cfg.dataDir;

        ExecStart = "${startServer}";

        # Exit code 8 = restart for update
        RestartForceExitStatus = [ 8 ];
        SuccessExitStatus = [
          0
          8
        ];
        Restart = "on-failure";
        RestartSec = 10;

        # Hardening
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.dataDir ];
        NoNewPrivileges = true;
      };
    };

    networking.firewall.allowedUDPPorts =
      let
        port = lib.toInt (lib.last (lib.splitString ":" cfg.bind));
      in
      mkIf cfg.openFirewall [ port ];
  };
}
