{
  services.authentik = {
    enable = true;
    host = "0.0.0.0";
    outposts.ldap.enable = false;
  };

  database.authentik = {
    passwordSecret = "authentik/postgres-password";
  };

  users.users.authentik = {
    name = "authentik";
    group = "authentik";
    isSystemUser = true;
  };
  users.groups.authentik = { };

  ingress.authentik = {
    subdomain = "authentik";
    port = 9000;
    letsencrypt = false;
  };

  sops.secrets = {
    "authentik/env" = { };
  };
}
