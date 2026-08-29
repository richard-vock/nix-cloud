{
  hosts,
  config,
  lib,
  pkgs,
  ...
}:
let
  buildPackages = with pkgs; [
    bash
    coreutils
    findutils
    gawk
    gcc
    git
    gnugrep
    gnumake
    gnused
    gzip
    nodejs_22
    openssh
    pkg-config
    python3
    rsync
    gnutar
  ];
in
{
  users.groups.gitlab-runner = { };
  users.users.gitlab-runner = {
    isSystemUser = true;
    group = "gitlab-runner";
    home = "/var/lib/gitlab-runner";
    createHome = true;
  };

  sops.secrets."gitlab-runner/authentication-token" = { };

  sops.templates."gitlab-runner-authentication-token-env".content = ''
    CI_SERVER_URL=https://code.${hosts.kaw-prod.domain}
    CI_SERVER_TOKEN=${config.sops.placeholder."gitlab-runner/authentication-token"}
  '';

  services.gitlab-runner = {
    enable = true;
    gracefulTermination = true;
    gracefulTimeout = "10min";

    services.kaw-shell = {
      authenticationTokenConfigFile = config.sops.templates."gitlab-runner-authentication-token-env".path;
      executor = "shell";
      description = "kaw NixOS VM runner";
      limit = 1;
      environmentVariables = {
        PATH = lib.makeBinPath buildPackages;
        PYTHON = "${pkgs.python3}/bin/python3";
        npm_config_python = "${pkgs.python3}/bin/python3";
      };
      # With GitLab runner authentication tokens, tags and "run untagged"
      # are configured in GitLab when creating/editing the runner.
    };

    extraPackages = buildPackages;
  };

  systemd.services.gitlab-runner.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = "gitlab-runner";
    Group = "gitlab-runner";
  };
}
