{
  pkgs,
  ...
}:
let
  server = "nexus";
  domain = "damogran.sh";
  email = "root@${domain}";
in
{
  imports = [
    # ./services/authentik.nix
    # ./services/gitlab.nix
    # ./services/kaw-web.nix
  ];
  boot.loader.grub = {
    devices = [ "/dev/nvme0n1" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  _module.args.server = server;
  _module.args.domain = domain;
  _module.args.email = email;

  security.sudo.configFile = ''
    Defaults:root,%wheel env_keep+=LOCALE_ARCHIVE
    Defaults:root,%wheel env_keep+=NIX_PATH
    Defaults lecture = never
  '';

  services.openssh = {
    enable = true;
    ports = [ 55522 ];
    settings = {
      PasswordAuthentication = false;
    };
  };

  services.fail2ban = {
    enable = true;
    jails.sshd.settings = {
      enabled = true;
      filter = "sshd";
      port = "55522";
    };
  };

  services.resolved.enable = true;
  services.dbus.implementation = "dbus";
  networking = {
    nameservers = [
      "1.1.1.1#one.one.one.one"
      "1.0.0.1#one.one.one.one"
    ];
    hostName = server;
    domain = domain;
    interfaces.enp35s0.ipv6.addresses = [
      {
        address = "2a01:4f8:242:261e::1";
        prefixLength = 64;
      }
    ];
    defaultGateway6 = {
      address = "fe80::1";
      interface = "enp35s0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [
        80
        443
        55522
      ];
      allowedUDPPorts = [ 55522 ];
    };

  };

  nix.settings."trusted-users" = [
    "root"
    "@wheel"
  ];

  sops.defaultSopsFile = ../secrets/nexus.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  environment.systemPackages = with pkgs; [
    neovim
    tmux
  ];

  system.stateVersion = "26.05";
}
