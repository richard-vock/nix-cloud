{
  config,
  pkgs,
  ...
}:
{
  services.hytale-server = {
    enable = true;
    serverJar = "/data/hytale/Server/HytaleServer.jar";
    assetsZip = "/data/hytale/Assets.zip";
    dataDir = "/data/hytale/server-data";
    openFirewall = true;
    jvmOpts = "-Xms4G -Xmx8G";
  };
}
