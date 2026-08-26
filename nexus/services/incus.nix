{
  ...
}:
{
  networking = {
    nftables.enable = true;
    firewall.trustedInterfaces = [ "incusbr0" ];
  };

  virtualisation.incus = {
    enable = true;
    ui.enable = false;

    preseed = {
      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.0.100.1/24";
            "ipv4.nat" = "true";
            "ipv6.address" = "none";
          };
        }
      ];

      storage_pools = [
        {
          name = "default";
          driver = "btrfs";
          config.source = "/pool";
        }
      ];

      profiles = [
        {
          name = "default";
          config = {
            "security.secureboot" = "false";
          };
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          };
        }
      ];
    };
  };
}
