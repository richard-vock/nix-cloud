{ lib, ... }:
{
  disko.devices = {
    disk = {
      disk1 = {
        device = lib.mkDefault "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "boot";
              size = "1M";
              type = "EF02";
            };
            esp = {
              name = "ESP";
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/";
                mountOptions = [
                  "noatime"
                  "compress=zstd"
                  "ssd"
                  "discard=async"
                ];
              };
            };
          };
        };
      };

      disk2 = {
        device = lib.mkDefault "/dev/nvme1n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            pool = {
              name = "pool";
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/pool";
                mountOptions = [
                  "noatime"
                  "compress=zstd"
                  "ssd"
                  "discard=async"
                ];
              };
            };
          };
        };
      };
    };
  };
}
