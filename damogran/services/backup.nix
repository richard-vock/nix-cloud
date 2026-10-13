{
  config,
  pkgs,
  ...
}:
let
  storageBoxUser = "u658328-sub1";
  storageBoxHost = "u658328-sub1.your-storagebox.de";
  storageBoxIdentityFile = config.sops.secrets."backup/storagebox_ed25519".path;
in
{
  systemd.tmpfiles.rules = [
    "d /var/backup/kaw-web 0750 root root -"
    "d /var/lib/borgbackup/kaw-web-db 0700 root root -"
  ];

  services.borgbackup.jobs.kaw-web-db = {
    paths = [ "/var/backup/kaw-web/db.sqlite" ];
    # The Storage Box subuser is already rooted at /home/backups/kaw-prod.
    # Keep this relative to that home, otherwise Borg resolves e.g.
    # backups/kaw-prod/kaw-web-db as /home/backups/kaw-prod/kaw-web-db.
    repo = "${storageBoxUser}@${storageBoxHost}:kaw-web-db";
    doInit = true;

    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.sops.secrets."backup/borg-passphrase".path}";
    };

    environment.BORG_RSH = "ssh -p 23 -i ${storageBoxIdentityFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/var/lib/borgbackup/kaw-web-db/known_hosts";

    compression = "auto,zstd,6";
    startAt = "03:15";
    persistentTimer = true;

    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 6;
    };

    readWritePaths = [
      "/var/backup/kaw-web"
      "/var/lib/borgbackup/kaw-web-db"
    ];

    preHook = ''
      install -d -m 0700 /var/lib/borgbackup/kaw-web-db
      install -d -m 0750 /var/backup/kaw-web

      ${pkgs.sqlite}/bin/sqlite3 /var/lib/kaw-web/db.sqlite ".backup '/var/backup/kaw-web/db.sqlite'"
      chmod 0640 /var/backup/kaw-web/db.sqlite
    '';
  };

  sops.secrets."backup/borg-passphrase" = { };
}
