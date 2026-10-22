{
  config,
  pkgs,
  ...
}:
let
  storageBoxUser = "u658328-sub2";
  storageBoxHost = "u658328-sub2.your-storagebox.de";
  storageBoxIdentityFile = config.sops.secrets."backup/storagebox_ed25519".path;
  snapshotDir = "/var/backup/vaultwarden/data";
  restartMarker = "/run/borgbackup-vaultwarden/restart-required";
  systemctl = "${pkgs.systemd}/bin/systemctl";
in
{
  systemd.tmpfiles.rules = [
    "d /var/backup/vaultwarden 0700 root root -"
    "d /var/lib/borgbackup/vaultwarden 0700 root root -"
  ];

  services.borgbackup.jobs.vaultwarden = {
    paths = [ snapshotDir ];
    # Relative to the Storage Box subuser's home, not the main account's home.
    repo = "${storageBoxUser}@${storageBoxHost}:vaultwarden";
    doInit = true;

    encryption = {
      mode = "repokey-blake2";
      passCommand = "${pkgs.coreutils}/bin/cat ${config.sops.secrets."backup/borg-passphrase".path}";
    };

    environment.BORG_RSH = "ssh -p 23 -i ${storageBoxIdentityFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/var/lib/borgbackup/vaultwarden/known_hosts";

    compression = "auto,zstd,6";
    startAt = "03:15";
    persistentTimer = true;

    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };

    readWritePaths = [
      "/var/backup/vaultwarden"
      "/var/lib/borgbackup/vaultwarden"
    ];

    preHook = ''
      # Refuse to start an intentionally stopped or uninitialized instance.
      test -f /var/lib/vaultwarden/db.sqlite3
      ${systemctl} is-active --quiet vaultwarden.service

      # Remove only this job's disposable staging data, never the live data.
      ${pkgs.coreutils}/bin/rm -rf -- ${snapshotDir}
      ${pkgs.coreutils}/bin/install -d -m 0700 ${snapshotDir}

      # ExecStopPost restores availability even if copying or validation fails.
      ${pkgs.coreutils}/bin/touch ${restartMarker}
      ${systemctl} stop vaultwarden.service
      ${pkgs.coreutils}/bin/cp -a /var/lib/vaultwarden/. ${snapshotDir}/
      test "$(${pkgs.sqlite}/bin/sqlite3 -readonly ${snapshotDir}/db.sqlite3 'PRAGMA integrity_check;')" = ok
      ${systemctl} start vaultwarden.service
      ${pkgs.coreutils}/bin/rm -- ${restartMarker}
      # Borg uploads the stable copy with Vaultwarden already running again.
    '';
  };

  systemd.services.borgbackup-job-vaultwarden.serviceConfig = {
    RuntimeDirectory = "borgbackup-vaultwarden";
    RuntimeDirectoryMode = "0700";
    ExecStopPost = pkgs.writeShellScript "vaultwarden-backup-cleanup" ''
      set -eu
      if test -e ${restartMarker}; then
        ${systemctl} start vaultwarden.service
      fi
      ${pkgs.coreutils}/bin/rm -rf -- ${snapshotDir}
    '';
  };

  sops.secrets."backup/borg-passphrase" = { };
}
