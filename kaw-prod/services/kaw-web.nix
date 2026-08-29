{
  config,
  hosts,
  pkgs,
  ...
}:
{
  users.users.kaw-web = {
    isSystemUser = true;
    group = "kaw-web";
    home = "/srv/kaw-web";
    createHome = true;
  };

  users.groups.kaw-web = { };

  systemd.tmpfiles.rules = [
    "d /srv/kaw-web 2775 kaw-web kaw-web -"
    "d /srv/kaw-web/releases 2775 kaw-web kaw-web -"
    "d /var/lib/kaw-web 0750 kaw-web kaw-web -"
    "d /var/lib/kaw-web/uploads 0750 kaw-web kaw-web -"
  ];

  sops.secrets."authentik/apps/kaw-auth-prod/client-id" = { };
  sops.secrets."authentik/apps/kaw-auth-prod/client-secret" = { };

  sops.templates."kaw-web-env" = {
    owner = "kaw-web";
    group = "kaw-web";
    mode = "0400";
    content = ''
      AUTHENTIK_CLIENT_ID=${config.sops.placeholder."authentik/apps/kaw-auth-prod/client-id"}
      AUTHENTIK_CLIENT_SECRET=${config.sops.placeholder."authentik/apps/kaw-auth-prod/client-secret"}
    '';
  };

  systemd.services.kaw-web = {
    description = "KAW SvelteKit website";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    # The first infra deploy happens before CI has uploaded an app release.
    # Skip cleanly until /srv/kaw-web/current points at a built SvelteKit app.
    unitConfig.ConditionPathExists = "/srv/kaw-web/current/build";

    environment = {
      HOST = "0.0.0.0";
      PORT = "3000";
      NODE_ENV = "production";
      PUBLIC_SITE_URL = "https://${hosts.kaw-prod.domain}";
      LOG_LEVEL = "INFO";
      DATABASE_PATH = "/var/lib/kaw-web/db.sqlite";
      UPLOADS_DIR = "/var/lib/kaw-web/uploads";
      PUBLIC_UPLOADS_BASE_PATH = "/uploads";
      EVENT_IMAGE_MAX_BYTES = "5242880";
      AUTHENTIK_BASE_URL = "https://authentik.${hosts.kaw-prod.domain}";
      AUTHENTIK_REDIRECT_URL = "https://${hosts.kaw-prod.domain}/auth/callback";
    };

    serviceConfig = {
      User = "kaw-web";
      Group = "kaw-web";
      WorkingDirectory = "/srv/kaw-web/current";
      ExecStart = "${pkgs.nodejs_22}/bin/node build";
      EnvironmentFile = config.sops.templates."kaw-web-env".path;
      Restart = "always";
      RestartSec = 5;
    };
  };

  networking.firewall.allowedTCPPorts = [
    3000
  ];
}
