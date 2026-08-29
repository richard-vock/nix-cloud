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
      hosts = {
        kaw-prod = {
          domain = "kulturausbesserungswerk.org";
          ip = "10.0.100.100";
        };
        runner = {
          ip = "10.0.100.101";
        };
      };
      mkSystem =
        name:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = inputs // {
            inherit hosts;
          };
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
        {
          nexus = mkSystem "nexus";
          kaw-prod = mkSystem "kaw-prod";
          runner = mkSystem "runner";
        }
      ];

      devShells."${system}".default = pkgs.mkShell {
        packages = [
          deploy-rs.packages."${system}".default
          nixos-anywhere.packages."${system}".default
          pkgs.age
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
          (pkgs.writeShellScriptBin "inject-vm-key" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            instance="''${1:-}"
            pubkey="''${2:-$HOME/.ssh/id_ed25519.pub}"
            account="''${3:-root}"
            jump_user="''${JUMP_USER:-admin}"
            jump_host="''${JUMP_HOST:-damogran.sh}"
            jump_port="''${JUMP_PORT:-55522}"

            if [ -z "$instance" ]; then
              echo "usage: inject-vm-key <incus-instance> [pubkey] [account]" >&2
              echo "example: inject-vm-key nixos-vm" >&2
              exit 1
            fi

            if [ ! -r "$pubkey" ]; then
              echo "public key not readable: $pubkey" >&2
              exit 1
            fi

            key=$(cat "$pubkey")
            printf -v quoted_instance %q "$instance"
            printf -v quoted_account %q "$account"
            printf -v quoted_key %q "$key"

            ssh -p "$jump_port" "$jump_user@$jump_host" \
              "bash -s -- $quoted_instance $quoted_account $quoted_key" <<'EOF'
            set -euo pipefail

            instance=$1
            account=$2
            key=$3
            workdir=$(mktemp -d)
            trap 'rm -rf "$workdir"' EXIT

            passwd_file=$workdir/passwd
            auth_file=$workdir/authorized_keys

            incus file pull "$instance/etc/passwd" "$passwd_file"

            home=
            while IFS=: read -r name _passwd _uid _gid _gecos dir _shell; do
              if [ "$name" = "$account" ]; then
                home=$dir
                break
              fi
            done < "$passwd_file"

            if [ -z "$home" ]; then
              echo "account not found: $account" >&2
              exit 1
            fi

            incus file pull "$instance$home/.ssh/authorized_keys" "$auth_file" 2>/dev/null || touch "$auth_file"

            if ! grep -qxF "$key" "$auth_file"; then
              printf '%s\n' "$key" >> "$auth_file"
            fi

            incus file push --create-dirs --mode 0600 "$auth_file" "$instance$home/.ssh/authorized_keys"
            incus exec "$instance" -- sh -c '
              set -eu
              export PATH=/run/current-system/sw/bin:/usr/bin:/bin:$PATH
              chmod 0700 "$1/.ssh"
              chown -R "$2" "$1/.ssh"
            ' sh "$home" "$account"
            EOF

            echo "installed $pubkey for $account in $instance via $jump_user@$jump_host:$jump_port"
          '')
          (pkgs.writeShellScriptBin "init-vm-sops-key" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail

            instance="''${1:-}"
            jump_user="''${JUMP_USER:-admin}"
            jump_host="''${JUMP_HOST:-damogran.sh}"
            jump_port="''${JUMP_PORT:-55522}"

            if [ -z "$instance" ]; then
              echo "usage: init-vm-sops-key <incus-instance>" >&2
              echo "example: init-vm-sops-key kaw-prod" >&2
              exit 1
            fi

            printf -v quoted_instance %q "$instance"

            if ssh -p "$jump_port" "$jump_user@$jump_host" \
              "incus file pull $quoted_instance/var/lib/sops-nix/key.txt -" >/dev/null 2>&1; then
              echo "$instance already has /var/lib/sops-nix/key.txt" >&2
              exit 1
            fi

            key_dir=$(mktemp -d)
            key_file="$key_dir/key.txt"
            trap 'rm -rf "$key_dir"' EXIT

            ${pkgs.age}/bin/age-keygen -o "$key_file" >/dev/null
            recipient=$(${pkgs.age}/bin/age-keygen -y "$key_file")

            ssh -p "$jump_port" "$jump_user@$jump_host" \
              "incus file push --create-dirs --mode 0600 - $quoted_instance/var/lib/sops-nix/key.txt" \
              < "$key_file"

            echo "installed /var/lib/sops-nix/key.txt in $instance via $jump_user@$jump_host:$jump_port"
            echo "age recipient for $instance:"
            echo "$recipient"
          '')
        ];
      };

      deploy.nodes = {
        nexus = {
          hostname = "damogran.sh";
          sshUser = "root";
          sshOpts = [
            "-p"
            "55522"
          ];
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."${system}".activate.nixos self.nixosConfigurations.nexus;
          };
        };
        kaw-prod = {
          hostname = hosts.kaw-prod.ip;
          sshUser = "root";
          sshOpts = [
            "-J"
            "admin@damogran.sh:55522"
          ];
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."${system}".activate.nixos self.nixosConfigurations.kaw-prod;
          };
        };

        runner = {
          hostname = hosts.runner.ip;
          sshUser = "root";
          sshOpts = [
            "-J"
            "admin@damogran.sh:55522"
          ];
          profiles.system = {
            user = "root";
            path = deploy-rs.lib."${system}".activate.nixos self.nixosConfigurations.runner;
          };
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
