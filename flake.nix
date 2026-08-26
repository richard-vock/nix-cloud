{
  description = "VPS Infrastructure Deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-anywhere,
      disko,
      deploy-rs,
      sops-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages."${system}";
      mkSystem =
        name:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = inputs;
          modules = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./modules/common.nix
            ./${name}/default.nix
            ./${name}/hardware-configuration.nix
            ./provisioning/${name}/disk-config.nix
          ];
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.attrsets.mergeAttrsList [
        { nexus = mkSystem "nexus"; }
      ];

      devShells."${system}".default = pkgs.mkShell {
        packages = [
          deploy-rs.packages."${system}".default
          nixos-anywhere.packages."${system}".default
          pkgs.openssh
          pkgs.sops
          (pkgs.writeShellScriptBin "provision" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            name=$1
            host_ip=$2
            ssh_opts=(
              -o StrictHostKeyChecking=no
              -o UserKnownHostsFile=/dev/null
              -o GlobalKnownHostsFile=/dev/null
              -o LogLevel=ERROR
            )

            if [ -z "''${name:-}" ] || [ -z "''${host_ip:-}" ]; then
              echo "usage: provision <name> <host-ip>" >&2
              exit 1
            fi

            nixos-anywhere \
              --ssh-option "StrictHostKeyChecking=no" \
              --ssh-option "UserKnownHostsFile=/dev/null" \
              --ssh-option "GlobalKnownHostsFile=/dev/null" \
              --ssh-option "LogLevel=ERROR" \
              --generate-hardware-config nixos-generate-config "./provisioning/$name/hardware-configuration.nix" \
              --flake "./provisioning#$name" \
              --target-host root@$host_ip

            cp ./provisioning/$name/hardware-configuration.nix ./$name/hardware-configuration.nix

            for _ in $(seq 1 60); do
              if ssh "''${ssh_opts[@]}" -p 55522 root@$host_ip true >/dev/null 2>&1; then
                break
              fi
              sleep 2
            done

            ssh "''${ssh_opts[@]}" -p 55522 root@$host_ip '
              set -euo pipefail
              install -d -m 0700 /var/lib/sops-nix
              if [ ! -f /var/lib/sops-nix/key.txt ]; then
                age-keygen -o /var/lib/sops-nix/key.txt >/dev/null
                chmod 600 /var/lib/sops-nix/key.txt
              fi
              echo "age recipient for $HOSTNAME:"
              age-keygen -y /var/lib/sops-nix/key.txt
            '
          '')
        ];
      };

      deploy.nodes = {
        nexus = {
          sshUser = "root";
          hostname = "kulturausbesserungswerk.org";
          sshOpts = [
            "-p"
            "55522"
          ];
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."${system}".activate.nixos self.nixosConfigurations.nexus;
          };
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
