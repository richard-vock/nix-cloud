{
  config,
  domain,
  hosts,
  pkgs,
  ...
}:
let
  headscaleDomain = "headscale.${domain}";
  magicDnsDomain = "net.${domain}";
  listenAddress = hosts.damogran.ip;
  listenPort = 8085;
  authentikIssuer = "https://authentik.${domain}/application/o/headscale/";
  waitForAuthentik = pkgs.writeShellScript "headscale-wait-for-authentik" ''
    set -euo pipefail
    url='${authentikIssuer}.well-known/openid-configuration'
    for attempt in $(seq 1 30); do
      if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 5 "$url" >/dev/null; then
        exit 0
      fi
      echo "Waiting for Authentik OIDC issuer ($url), attempt $attempt" >&2
      sleep 2
    done
    echo "Authentik OIDC issuer still unavailable after 30 attempts" >&2
    exit 1
  '';
in
{
  services.headscale = {
    enable = true;
    address = listenAddress;
    port = listenPort;

    settings = {
      server_url = "https://${headscaleDomain}";
      dns = {
        magic_dns = true;
        base_domain = magicDnsDomain;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
      logtail.enabled = false;
      oidc = {
        issuer = authentikIssuer;
        # Supplied at runtime through HEADSCALE_OIDC_CLIENT_ID below.
        client_secret_path = config.sops.secrets."headscale/oidc-client-secret".path;
        scope = [
          "openid"
          "profile"
          "email"
        ];
      };
    };
  };

  # Nexus terminates TLS and proxies directly to the VM.
  networking.firewall.allowedTCPPorts = [ listenPort ];

  services.authentik.apps.headscale = {
    redirectURL = "https://headscale.${domain}/oidc/callback";
  };

  systemd.services.headscale = {
    after = [
      "authentik-worker.service"
      "authentik-server.service"
      "authentik-managed-blueprints.service"
    ];
    requires = [
      "authentik-worker.service"
      "authentik-server.service"
      "authentik-managed-blueprints.service"
    ];
    serviceConfig = {
      ExecStartPre = waitForAuthentik; # ensure Authentik's OIDC endpoint is reachable
      EnvironmentFile = config.sops.templates."headscale.env".path;
    };
  };

  sops.templates."headscale.env" = {
    content = ''
      HEADSCALE_OIDC_CLIENT_ID=${config.sops.placeholder."authentik/apps/headscale/client-id"}
    '';
    restartUnits = [ "headscale.service" ];
  };

  # A separate file lets Headscale read the shared credential without granting
  # access to Authentik's other secrets.
  sops.secrets."headscale/oidc-client-secret" = {
    key = "authentik/apps/headscale/client-secret";
    restartUnits = [ "headscale.service" ];
    owner = "headscale";
    group = "headscale";
    mode = "0400";
  };
}
