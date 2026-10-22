{ pkgs, ... }:
{
  services.tailscale = {
    enable = true;
    authKeyFile = null; # we’ll supply the key manually
    disableTaildrop = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraDaemonFlags = [ "--no-logs-no-support" ];
    package = pkgs.tailscale;
  };
}
