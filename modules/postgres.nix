{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.database;

  databases = lib.attrValues cfg;
  databasesWithPasswords = lib.filter (db: db.passwordSecret != null) databases;

  sopsInstallSecretsUnit = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";

  passwordScript = lib.concatMapStringsSep "\n" (db: ''
    password="$(${pkgs.coreutils}/bin/cat ${
      lib.escapeShellArg config.sops.secrets.${db.passwordSecret}.path
    })"
    ${config.services.postgresql.package}/bin/psql \
      --port=5432 \
      --set=ON_ERROR_STOP=1 \
      --set=role=${lib.escapeShellArg db.user} \
      --set=password="$password" <<'SQL'
    ALTER USER :"role" WITH PASSWORD :'password';
    SQL
  '') databasesWithPasswords;
in
{
  options.database = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            user = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "PostgreSQL role to ensure for this service.";
            };

            database = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "PostgreSQL database to ensure for this service.";
            };

            passwordSecret = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "authentik/postgres-password";
              description = ''
                Optional sops-nix secret containing the PostgreSQL password for
                this service's role. The secret is read at activation time and
                is not embedded in the Nix store.
              '';
            };

            superuser = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to grant the PostgreSQL role SUPERUSER.";
            };
          };
        }
      )
    );
    default = { };
    description = "Per-service PostgreSQL databases and roles to provision.";
  };

  config = lib.mkIf (cfg != { }) {
    systemd.services.postgresql = {
      after = sopsInstallSecretsUnit;
      requires = sopsInstallSecretsUnit;
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = lib.unique (map (db: db.database) databases);
      ensureUsers = map (db: {
        name = db.user;
        ensureDBOwnership = db.user == db.database;
        ensureClauses = {
          login = true;
          superuser = db.superuser;
        };
      }) databases;
    };

    systemd.services.postgresql-set-passwords = {
      description = "Set PostgreSQL user passwords";
      after = sopsInstallSecretsUnit ++ [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      requires = sopsInstallSecretsUnit ++ [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      partOf = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail
        ${passwordScript}
      '';
    };

    sops.secrets = lib.listToAttrs (
      map (db: {
        name = db.passwordSecret;
        value = {
          owner = "postgres";
          group = "postgres";
          mode = "0400";
        };
      }) databasesWithPasswords
    );
  };
}
