{
  hosts,
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
            "limits.memory" = "8GiB";
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
              size = "100GiB";
              type = "disk";
            };
          };
        }
        {
          name = "kaw-prod";
          config = { };
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
              "ipv4.address" = hosts.kaw-prod.ip;
            };
          };
        }
        {
          name = "runner";
          config = { };
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
              "ipv4.address" = hosts.runner.ip;
            };
          };
        }
      ];
    };
  };
}
