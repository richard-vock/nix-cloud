{ config, ... }:
let
  keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIELrPK2tUl9GFBeHEaafeKMuMvLbqXPFRVmphfjW8cuv nrtn@posteo.net"
  ];
in
{
  sops.secrets."users/admin/pw" = {
    neededForUsers = true;
  };

  users.users.root.openssh.authorizedKeys.keys = keys;

  users.users.admin = {
    name = "admin";
    group = "users";
    hashedPasswordFile = config.sops.secrets."users/admin/pw".path;
    isNormalUser = true;
    createHome = true;
    extraGroups = [
      "incus-admin"
      "wheel"
    ];
    openssh.authorizedKeys.keys = keys;
  };

  programs.bash.interactiveShellInit = ''
    set -o vi
  '';
}
