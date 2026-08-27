{
  config,
  lib,
  pkgs,
  domain,
  email,
  ...
}:

let
  ingresses = config.ingress;

  mkVirtualHost =
    name: ingress:
    let
      hostName = if ingress.host != null then ingress.host else "${ingress.subdomain}.${domain}";
      upstream = "http://${ingress.address}:${builtins.toString ingress.port}";
    in
    {
      name = hostName;
      value = {
        enableACME = ingress.letsencrypt;
        forceSSL = ingress.letsencrypt;
        locations."/" = {
          proxyPass = upstream;
          proxyWebsockets = true;
        };
      };
    };

  needsAcme = lib.any (ingress: ingress.letsencrypt) (lib.attrValues ingresses);
in
with lib;
{
  options.ingress = mkOption {
    type = types.attrsOf (
      types.submodule (
        { config, ... }:
        {
          options = {
            subdomain = mkOption {
              type = types.str;
              description = "Subdomain handled by the reverse proxy.";
            };

            host = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override the fully qualified host name (defaults to subdomain.${domain}).";
            };

            letsencrypt = mkOption {
              type = types.bool;
              default = true;
              description = "Request and use a Let's Encrypt certificate for this subdomain.";
            };

            address = mkOption {
              type = types.str;
              default = "127.0.0.1";
              description = "Address of the backend service.";
            };

            port = mkOption {
              type = types.port;
              default = 8080;
              description = "Port of the backend service.";
            };

          };
        }
      )
    );

    default = { };
    description = "Simple reverse proxy mapping between subdomains and backend services.";
  };

  config = mkMerge [
    {
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        recommendedGzipSettings = true;
        virtualHosts = builtins.listToAttrs (mapAttrsToList mkVirtualHost ingresses);
      };
    }

    (mkIf needsAcme {
      security.acme = {
        acceptTerms = true;
        defaults.email = email;
      };
    })
  ];
}
