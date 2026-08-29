{
  hosts,
  ...
}:
{
  ingress.authentik-kaw-prod = {
    host = "authentik.${hosts.kaw-prod.domain}";
    address = hosts.kaw-prod.ip;
    port = 9000;
    letsencrypt = true;
  };

  ingress.gitlab-kaw-prod = {
    host = "code.${hosts.kaw-prod.domain}";
    address = hosts.kaw-prod.ip;
    port = 80;
    letsencrypt = true;
  };

  ingress.kaw-web = {
    host = hosts.kaw-prod.domain;
    address = hosts.kaw-prod.ip;
    port = 3000;
    letsencrypt = true;
  };
}
