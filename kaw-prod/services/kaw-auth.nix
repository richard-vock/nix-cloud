{
  hosts,
  ...
}:
{
  services.authentik.apps."kaw-auth-prod" = {
    redirectURL = "http://${hosts.kaw-prod.domain}:5173/auth/callback";
  };
  services.authentik.apps."kaw-auth-dev" = {
    redirectURL = "http://localhost:5173/auth/callback";
  };
  services.authentik.apps."kaw-auth-agent" = {
    redirectURL = "http://dev.net.damogran.cc:5173/auth/callback";
  };
}
