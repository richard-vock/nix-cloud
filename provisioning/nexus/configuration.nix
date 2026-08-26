{
  modulesPath,
  lib,
  pkgs,
  ...
}@args:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh = {
    enable = true;
    ports = [ 55522 ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = lib.mkForce "yes";
    };
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.age
    pkgs.curl
    pkgs.gitMinimal
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELrPK2tUl9GFBeHEaafeKMuMvLbqXPFRVmphfjW8cuv nrtn@posteo.net"
  ];

  system.stateVersion = "26.05";
}
