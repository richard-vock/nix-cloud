## Deployment

Basic configs for provisioning are in `provisioning/[host]`.
For creating a new host copy another config and add an entry to `provisioning/flake.nix`.
In any case make sure your ssh key is set in the `users.users.root.openssh.authorizedKeys.keys` list in `provisioning/[host]/configuration.nix`.

On nexus create a VM/Container and wait for it to get an IP.

```
incus launch images:nixos/26.05 [name] --vm
watch watch incus network list-leases incusbr0
```

Set the IP as the target host in `flake.nix`. Then

```
nix develop
inject-vm-key [name]
init-vm-sops-key [name]
```

The latter command prints an age key. Add that to ` .sops.yaml` and rekey using

```
sops updatekeys secrets/[name].yaml
```

Then deploy using

```
deploy .#name
```
