{
  config,
  lib,
  pkgs,
  domain,
  ...
}:

let
  cfg = config.services.authentik;
  customPropertyMappingsByName = builtins.listToAttrs (
    map (mapping: {
      name = mapping.name;
      value = mapping;
    }) cfg.customPropertyMappings
  );
  renderManagedScopeMappings =
    scopes:
    lib.concatMapStrings (
      scope:
      "                - !Find [authentik_providers_oauth2.scopemapping, [managed, ${scopeToManaged scope}]]\n"
    ) scopes;
  renderCustomScopeMappings =
    scopes:
    lib.concatMapStrings (
      scope: "                - !Find [authentik_providers_oauth2.scopemapping, [name, ${scope}]]\n"
    ) scopes;
  leadingSpaceCount =
    line: builtins.stringLength (builtins.elemAt (builtins.match "([ ]*).*" line) 0);
  dedentMultiline =
    value:
    let
      normalized = builtins.replaceStrings [ "\t" "\r" ] [ "  " "" ] value;
      lines = lib.splitString "\n" normalized;
      nonEmptyLines = builtins.filter (line: line != "") lines;
      minIndent =
        if nonEmptyLines == [ ] then
          0
        else
          lib.foldl' lib.min (leadingSpaceCount (builtins.head nonEmptyLines)) (
            map leadingSpaceCount (builtins.tail nonEmptyLines)
          );
      stripIndent =
        line:
        if line == "" then
          ""
        else
          builtins.substring minIndent (builtins.stringLength line - minIndent) line;
    in
    map stripIndent lines;
  renderBlueprintLiteral =
    value: lib.concatMapStrings (line: "                  ${line}\n") (dedentMultiline value);
  scopeToManaged =
    scope:
    if lib.hasPrefix "goauthentik.io/" scope then
      scope
    else
      "goauthentik.io/providers/oauth2/${
        {
          openid = "scope-openid";
          email = "scope-email";
          profile = "scope-profile";
        }
        .${scope} or "scope-${scope}"
      }";
  appBlueprintTemplates = lib.mapAttrs' (name: app: {
    name = "authentik/blueprints/${name}.yaml";
    value = {
      owner = "authentik";
      group = "authentik";
      mode = "0400";
      restartUnits = [ "authentik-managed-blueprints.service" ];
      content = ''
                version: 1
                metadata:
                  name: ${name} app
                entries:
                  - model: authentik_providers_oauth2.oauth2provider
                    id: ${name}-provider
                    identifiers:
                      client_id: ${config.sops.placeholder."authentik/apps/${name}/client-id"}
                    attrs:
                      name: ${name} provider
                      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-explicit-consent]]
                      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
                      redirect_uris:
                        - matching_mode: strict
                          url: ${app.redirectURL}
                      client_secret: ${config.sops.placeholder."authentik/apps/${name}/client-secret"}
                      client_type: confidential
                      signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
                      property_mappings:
        ${renderManagedScopeMappings app.scopes}${renderCustomScopeMappings app.customScopes}

                  - model: authentik_core.application
                    identifiers:
                      slug: ${name}
                    attrs:
                      name: ${name}
                      provider: !KeyOf ${name}-provider
      '';
    };
  }) cfg.apps;
  customPropertyMappingBlueprintTemplates = builtins.listToAttrs (
    map (mapping: {
      name = "authentik/blueprints/custom-property-mapping-${lib.strings.sanitizeDerivationName mapping.name}.yaml";
      value = {
        owner = "authentik";
        group = "authentik";
        mode = "0400";
        restartUnits = [ "authentik-managed-blueprints.service" ];
        content = ''
                    version: 1
                    metadata:
                      name: ${mapping.name} custom property mapping
                    entries:
                      - model: authentik_providers_oauth2.scopemapping
                        identifiers:
                          name: ${mapping.name}
                        attrs:
                          name: ${mapping.name}
                          scope_name: ${mapping.scopeName}
                          description: ${mapping.description}
                          expression: |
          ${renderBlueprintLiteral mapping.expression}
        '';
      };
    }) cfg.customPropertyMappings
  );
  blueprintTemplates = appBlueprintTemplates // customPropertyMappingBlueprintTemplates;
  managedBlueprintEntries = lib.mapAttrsToList (name: _: {
    inherit name;
    instanceName = baseNameOf name;
    templatePath = config.sops.templates.${name}.path;
  }) blueprintTemplates;
  managedBlueprintsBootstrap = pkgs.writeText "authentik-managed-blueprints.py" (
    ''
      import time
      from pathlib import Path

      from authentik.blueprints.models import BlueprintInstance
      from authentik.blueprints.v1.importer import Importer
      from authentik.tenants.models import Tenant

      BLUEPRINTS = [
    ''
    + lib.concatMapStringsSep "\n" (entry: ''
      {
          "name": ${builtins.toJSON entry.instanceName},
          "template_path": ${builtins.toJSON entry.templatePath},
      },'') managedBlueprintEntries
    + ''
      ]

      REQUIRED_FLOW_SLUGS = {
          "default-provider-authorization-explicit-consent",
          "default-provider-invalidation-flow",
      }

      def apply_for_tenant():
          from authentik.flows.models import Flow

          existing = set()
          for _ in range(30):
              existing = set(
                  Flow.objects.filter(slug__in=REQUIRED_FLOW_SLUGS).values_list("slug", flat=True)
              )
              if existing == REQUIRED_FLOW_SLUGS:
                  break
              time.sleep(2)
          else:
              missing = ", ".join(sorted(REQUIRED_FLOW_SLUGS - existing))
              raise RuntimeError(f"Required default authentik flows not available: {missing}")

          for blueprint in BLUEPRINTS:
              content = Path(blueprint["template_path"]).read_text(encoding="utf-8")
              instance, _ = BlueprintInstance.objects.update_or_create(
                  name=blueprint["name"],
                  path="",
                  defaults={
                      "content": content,
                      "context": {},
                      "enabled": True,
                  },
              )
              importer = Importer.from_string(content, instance.context)
              valid, logs = importer.validate()
              if not valid:
                  rendered = "; ".join(log.event for log in logs)
                  raise RuntimeError(f"Blueprint {instance.name} failed validation: {rendered}")
              if not importer.apply():
                  raise RuntimeError(f"Blueprint {instance.name} failed to apply")

      for tenant in Tenant.objects.filter(ready=True):
          with tenant:
              apply_for_tenant()
    ''
  );
in
with lib;
{
  options.services.authentik = {
    enable = mkEnableOption (
      lib.mdDoc "authentik, the open-source Identity Provider that emphasizes flexibility and versatility"
    );
    package = mkPackageOption pkgs "authentik" {
      default = [ "authentik" ];
    };
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };
    outposts.ldap = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption (lib.mdDoc "the authentik ldap outpost");
          package = mkPackageOption pkgs "authentik-outposts.ldap" {
            default = [
              "authentik-outposts"
              "ldap"
            ];
          };
          host = mkOption {
            type = types.str;
            default = "127.0.0.1";
          };
        };
      };
    };
    apps = mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              redirectURL = mkOption {
                type = types.str;
                description = "OAuth2 redirect URL.";
              };
              scopes = mkOption {
                type = types.listOf types.str;
                default = [
                  "openid"
                  "email"
                  "profile"
                ];
                description = "Scope mappings (by managed name suffix) to attach to the provider.";
              };
              customScopes = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Names of custom scopes to attach. Define using services.authentik.customPropertyMappings.";
              };
            };
          }
        )
      );
      default = { };
      description = "OAuth2 applications to configure in authentik. The key is used as the slug for the application and the client_id for the provider.";
    };
    customPropertyMappings = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
            };
            scopeName = mkOption {
              type = types.str;
            };
            description = mkOption {
              type = types.str;
            };
            expression = mkOption {
              type = types.str;
            };
          };
        }
      );
      default = [ ];
      description = "Custom scope mappings to attach to the provider. The name attribute is used as the identifier for the scope, and the expression attribute is used as the expression for the scope mapping.";
    };
  };

  config = mkIf cfg.enable {
    assertions = flatten (
      mapAttrsToList (name: app: [
        {
          assertion = all (scope: builtins.hasAttr scope customPropertyMappingsByName) app.customScopes;
          message = "services.authentik.apps.${name}.customScopes must reference names defined in services.authentik.customPropertyMappings";
        }
      ]) cfg.apps
    );

    systemd.services.authentik-server = {
      description = "authentik server";
      after = [
        "network.target"
        "postgresql.service"
        "postgresql-set-passwords.service"
      ];
      requires = [
        "postgresql.service"
        "postgresql-set-passwords.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.bash ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/ak server";
        EnvironmentFile = "/run/secrets/authentik/env";
        User = "authentik";
        Group = "authentik";
        Restart = "always";
        RestartSec = 3;
        RuntimeDirectory = "authentik";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter = "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        ConfigurationDirectory = "authentik";
        Environment = [
          "AUTHENTIK_HOST=https://authentik.${domain}/"
          "AUTHENTIK_LISTEN__HTTP=${cfg.host}:9000"
        ];
      };
    };

    systemd.services.authentik-worker = {
      description = "authentik worker";
      after = [
        "network.target"
        "postgresql.service"
        "postgresql-set-passwords.service"
      ];
      requires = [
        "postgresql.service"
        "postgresql-set-passwords.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.bash ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/ak worker";
        EnvironmentFile = "/run/secrets/authentik/env";
        User = "authentik";
        Group = "authentik";
        Restart = "always";
        RestartSec = 3;
        RuntimeDirectory = "authentik";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter = "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        ConfigurationDirectory = "authentik";
        Environment = [
          "AUTHENTIK_HOST=https://authentik.${domain}/"
        ];
      };
    };

    systemd.services.authentik-ldap-outpost = mkIf cfg.outposts.ldap.enable {
      description = "authentik ldap outpost";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.bash ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.outposts.ldap.package}/bin/ldap";
        EnvironmentFile = "/run/secrets/authentik/env";
        Environment = [
          "AUTHENTIK_LISTEN__LDAPS=127.0.0.1:6636"
          "AUTHENTIK_LISTEN__LDAP=127.0.0.1:3389"
          "AUTHENTIK_HOST=https://authentik.${domain}/"
        ];
        User = "authentik";
        Group = "authentik";
        Restart = "always";
        RestartSec = 3;
        RuntimeDirectory = "authentik";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallFilter = "~@cpu-emulation @keyring @module @obsolete @raw-io @reboot @swap @sync";
        ConfigurationDirectory = "authentik";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      };
    };

    services.redis.servers.authentik = {
      enable = true;
      port = 6379;
    };

    sops.secrets = builtins.listToAttrs (
      (mapAttrsToList (name: app: {
        name = "authentik/apps/${name}/client-id";
        value = {
          owner = "authentik";
          group = "authentik";
          mode = "0400";
        };
      }) cfg.apps)
      ++ (mapAttrsToList (name: app: {
        name = "authentik/apps/${name}/client-secret";
        value = {
          owner = "authentik";
          group = "authentik";
          mode = "0400";
        };
      }) cfg.apps)
    );

    sops.templates = blueprintTemplates;

    systemd.services.authentik-managed-blueprints =
      let
        sopsInstallSecretsUnit = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
      in
      {
        description = "bootstrap managed authentik blueprints";
        after = sopsInstallSecretsUnit ++ [
          "postgresql.service"
          "authentik-server.service"
          "authentik-worker.service"
        ];
        requires = sopsInstallSecretsUnit ++ [
          "postgresql.service"
          "authentik-server.service"
          "authentik-worker.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "authentik";
          Group = "authentik";
          EnvironmentFile = "/run/secrets/authentik/env";
        };
        environment.AUTHENTIK_HOST = "https://authentik.${domain}/";
        script = ''
          set -euo pipefail
          ${cfg.package}/bin/ak shell < ${managedBlueprintsBootstrap}
        '';
      };

    systemd.timers.authentik-managed-blueprints = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "45s";
        OnUnitActiveSec = "5m";
        Persistent = true;
      };
    };

  };
}
