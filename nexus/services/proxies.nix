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
}
