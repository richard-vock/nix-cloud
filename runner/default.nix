{
  hosts,
  lib,
  pkgs,
  ...
}:
let
  server = "runner";
in
{
  imports = [
    ./services/gitlab-runner.nix
  ];

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  boot.loader.grub = {
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
  _module.args.domain = "local";
  _module.args.email = "root@${server}.local";

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
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        55522
      ];
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

  sops.defaultSopsFile = ../secrets/runner.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  environment.systemPackages = with pkgs; [
    git
    neovim
    nodejs_22
    openssh
    rsync
    tmux
  ];

  system.stateVersion = "26.05";
}
