{
  config,
  domain,
  email,
  ...
}:
let
  hostName = "code.${domain}";
in
{
  services.authentik.apps.gitlab = {
    redirectURL = "https://${hostName}/users/auth/openid_connect/callback";
  };

  services.gitlab = {
    enable = true;
    host = hostName;
    https = true;
    port = 443;
    initialRootEmail = email;
    initialRootPasswordFile = config.sops.secrets."gitlab/initial-root-password".path;
    secrets = {
      secretFile = config.sops.secrets."gitlab/secrets/secret".path;
      dbFile = config.sops.secrets."gitlab/secrets/db".path;
      otpFile = config.sops.secrets."gitlab/secrets/otp".path;
      jwsFile = config.sops.secrets."gitlab/secrets/jws".path;
      activeRecordPrimaryKeyFile = config.sops.secrets."gitlab/secrets/active-record-primary-key".path;
      activeRecordDeterministicKeyFile =
        config.sops.secrets."gitlab/secrets/active-record-deterministic-key".path;
      activeRecordSaltFile = config.sops.secrets."gitlab/secrets/active-record-salt".path;
    };
    extraConfig = {
      gitlab = {
        email_from = "gitlab-no-reply@${domain}";
        email_display_name = "GitLab";
        email_reply_to = "gitlab-no-reply@${domain}";
      };
      omniauth = {
        enabled = true;
        allow_single_sign_on = [ "openid_connect" ];
        block_auto_created_users = false;
        providers = [
          {
            name = "openid_connect";
            label = "Authentik";
            args = {
              name = "openid_connect";
              scope = [
                "openid"
                "email"
                "profile"
              ];
              response_type = "code";
              issuer = "https://authentik.${domain}/application/o/gitlab/";
              discovery = true;
              client_auth_method = "query";
              uid_field = "preferred_username";
              client_options = {
                identifier = {
                  _secret = config.sops.templates."gitlab/oidc-client-id".path;
                };
                secret = {
                  _secret = config.sops.templates."gitlab/oidc-client-secret".path;
                };
                redirect_uri = "https://${hostName}/users/auth/openid_connect/callback";
              };
            };
          }
        ];
      };
    };
  };

  services.nginx.virtualHosts.${hostName} = {
    locations."/" = {
      proxyPass = "http://unix:/run/gitlab/gitlab-workhorse.socket";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-Port 443;
      '';
    };
  };

  sops.secrets = {
    "gitlab/initial-root-password" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/db" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/otp" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/jws" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/active-record-primary-key" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/active-record-deterministic-key" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
    "gitlab/secrets/active-record-salt" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
    };
  };

  sops.templates = {
    "gitlab/oidc-client-id" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      content = config.sops.placeholder."authentik/apps/gitlab/client-id";
    };
    "gitlab/oidc-client-secret" = {
      owner = "gitlab";
      group = "gitlab";
      mode = "0400";
      content = config.sops.placeholder."authentik/apps/gitlab/client-secret";
    };
  };
}
