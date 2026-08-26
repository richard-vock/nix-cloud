{ pkgs, ... }:
{
  time.timeZone = "UTC";

  nix = {
    package = pkgs.nix;
    extraOptions = "experimental-features = nix-command flakes";
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  environment.systemPackages = with pkgs; [
    nettools
  ];
}
