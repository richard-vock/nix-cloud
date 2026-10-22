{ config, domain, pkgs, ... }:
let
  hostName = "bitwarden.${domain}";
in
{
  services.vaultwarden = {
    enable = true;
    environmentFile = config.sops.secrets."vaultwarden/env".path;
    backupDir = "/data/vaultwarden";
    config = {
      SIGNUPS_ALLOWED = false;
      # Disable all outgoing mail, even with SMTP credentials in the secret env.
      _ENABLE_SMTP = false;
      _ENABLE_EMAIL_2FA = false;
      DOMAIN = "https://${hostName}";
      SHOW_PASSWORD_HINT = false;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      ROCKET_LOG = "critical";
    };
  };

  # The upstream backup runs before Vaultwarden. On first activation its
  # copy glob fails on the empty data directory; skip until initialization.
  systemd.services.backup-vaultwarden.serviceConfig.ExecCondition =
    "${pkgs.coreutils}/bin/test -f /var/lib/vaultwarden/rsa_key.pem";

  # Terminate TLS here, not on the public Nexus proxy, preserving client IPs.
  ingress.vaultwarden = {
    subdomain = "bitwarden";
    port = 8222;
    tailscaleOnly = true;
  };

  security.acme.certs.${hostName} = {
    webroot = null; # Disable Nginx's default HTTP challenge in favour of DNS.
    dnsProvider = "cloudflare";
    environmentFile = config.sops.secrets."cloudflare/dns-api-token-env".path;
    dnsPropagationCheck = true;
    # Public zone discovery must bypass Headscale's private DNS override.
    dnsResolver = "1.1.1.1:53";
  };

  services.headscale.settings.dns.extra_records = [
    {
      name = hostName;
      type = "A";
      value = "100.64.0.3";
    }
  ];

  services.authentik = {
    apps.vaultwarden = {
      redirectURL = "https://${hostName}/identity/connect/oidc-signin";
      # The custom email scope replaces the default (email_verified = False).
      scopes = [ "openid" "profile" ];
      customScopes = [ "Verified Email" ];
    };
    customPropertyMappings = [
      {
        name = "Verified Email";
        scopeName = "email";
        description = "Mark email addresses as verified for Vaultwarden, matching the original host.";
        expression = ''
          return {
            "email": request.user.email,
            "email_verified": True
          }
        '';
      }
    ];
  };

  sops.secrets = {
    "vaultwarden/env" = {
      owner = "vaultwarden";
      restartUnits = [ "vaultwarden.service" ];
    };
    "cloudflare/dns-api-token-env" = { };
  };
}
