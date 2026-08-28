{
  hosts,
  lib,
  pkgs,
  ...
}:
let
  server = "kaw-prod";
  domain = hosts.kaw-prod.domain;
  email = "root@${domain}";
in
{
  imports = [
    ../modules/postgres.nix
    ../modules/reverse-proxy.nix
    ../modules/authentik.nix
    ./services/authentik.nix
    ./services/gitlab.nix
    ./services/kaw-auth.nix
  ];
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  boot.loader.grub = {
    # without mkForce disko still adds /dev/sda
    devices = lib.mkForce [ "nodev" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
    extraConfig = ''
      serial --unit=0 --speed=115200
      terminal_input serial console
      terminal_output serial console
    '';
  };

  systemd.services."serial-getty@ttyS0".wantedBy = [ "getty.target" ];

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
    ports = [
      22
      55522
    ];
    settings = {
      PasswordAuthentication = false;
    };
  };

  services.fail2ban = {
    enable = true;
    jails.sshd.settings = {
      enabled = true;
      filter = "sshd";
      port = "22";
    };
  };

  services.resolved.enable = true;

  virtualisation.incus.agent.enable = true;

  networking = {
    nameservers = [
      "1.1.1.1#one.one.one.one"
      "1.0.0.1#one.one.one.one"
    ];
    hostName = server;
    domain = domain;
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        80
        443
        9000
      ];
      #allowedUDPPorts = [ ];
    };

  };

  systemd.network.networks."50-ethernet" = {
    matchConfig.Name = [
      "en*"
      "eth*"
    ];
    linkConfig.RequiredForOnline = "routable";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
  };

  nix.settings."trusted-users" = [
    "root"
    "@wheel"
  ];

  sops.defaultSopsFile = ../secrets/kaw-prod.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  sops.secrets."backup/storagebox_ed25519" = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  environment.systemPackages = with pkgs; [
    neovim
    tmux
  ];

  system.stateVersion = "26.05";
}
