{ config, lib, pkgs, ... }:

let
  arr-sync-lib = import ./arr-sync-lib.nix { inherit config lib pkgs; };
  arr-sync-py = pkgs.callPackage ../../packages/nixarr-py { };
  inherit (arr-sync-lib)
    arrDownloadClientConfigModule
    arrDownloadClientConfigType;
  inherit (pkgs.writers)
    writeJSON
    writePython3Bin;
  airvpn-secret-file = ../../secrets/airvpn-wireguard.age;
  radarr-domain =
    "${config.site.apps.radarr.subdomain}.${config.site.domain}";
  vpn-enabled = config.site.apps.radarr.vpn.enable;
  vpn-gateway-address = "192.168.15.1";
  radarr-upstream =
    if vpn-enabled
    then "${vpn-gateway-address}:${toString config.site.apps.radarr.port}"
    else ":${toString config.site.apps.radarr.port}";
  settings-sync = config.site.apps.radarr.settings-sync;
  sync-settings = writePython3Bin "nixarr-sync-radarr-settings" {
    libraries = [ arr-sync-py ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./radarr-sync-settings.py);
  wantedServices = [ "radarr-api.service" ];
  vpn-accessible-from =
    [ "127.0.0.1" ]
    ++ lib.optionals config.site.apps.radarr.vpn.exposeOnLAN [
      "192.168.1.0/24"
      "192.168.0.0/24"
    ]
    ++ config.site.apps.radarr.vpn.accessibleFrom;
  reverse-proxy = upstream: ''
    import auth
    reverse_proxy ${upstream}
  '';
in {
  options.site.apps.radarr.settings-sync = {
    downloadClients = lib.mkOption {
      type = lib.types.listOf (arrDownloadClientConfigType "radarr");
      default = [ ];
      description = "Additional Radarr download clients to reconcile automatically.";
    };
    transmission = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically keep Transmission configured as a Radarr download client.";
      };
      config = lib.mkOption {
        type = lib.types.submodule [
          (arrDownloadClientConfigModule "radarr")
          {
            config = {
              name = "Transmission";
              implementation = "Transmission";
              enable = true;
              fields = {
                # We can use localhost even if Radarr or Transmission are in
                # the VPN because the namespace port mapping keeps the
                # Transmission port reachable.
                host = "localhost";
                port = config.site.apps.transmission.port;
                useSsl = false;
              };
            };
          }
        ];
        default = { };
        description = "Default Radarr download-client configuration for Transmission.";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = (!vpn-enabled) || builtins.pathExists airvpn-secret-file;
        message = "Radarr VPN requires ../../secrets/airvpn-wireguard.age to exist.";
      }
      {
        assertion = (!settings-sync.transmission.enable) || config.site.apps.transmission.enabled;
        message = "Radarr Transmission sync requires the Transmission module to be enabled.";
      }
    ];

    site.apps.radarr.settings-sync.downloadClients = lib.mkIf settings-sync.transmission.enable [
      settings-sync.transmission.config
    ];

    site.apps.radarr.enabled = true;

    age.secrets = lib.mkIf vpn-enabled {
      airvpn-wireguard = {
        owner = "root";
        group = "root";
        mode = "0400";
        file = airvpn-secret-file;
      };
    };

    users.users.radarr = {
      isSystemUser = true;
      group = "users";
      home = config.site.apps.radarr.dir;
      extraGroups = [ "radarr-api" ];
    };

    systemd.tmpfiles.rules = [
      "d ${config.site.apps.radarr.dir} 0750 radarr users - -"
    ];

    services.radarr = {
      enable = true;
      package = pkgs.radarr;
      user = "radarr";
      group = "users";
      settings.server.port = config.site.apps.radarr.port;
      openFirewall = false;
      dataDir = config.site.apps.radarr.dir;
    };

    systemd.services.radarr.environment.RADARR__AUTHENTICATIONMETHOD = "External";

    systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";

    systemd.services.radarr.vpnConfinement = lib.mkIf vpn-enabled {
      enable = true;
      vpnNamespace = "wg";
    };

    systemd.services.radarr-sync-config = {
      description = ''
        Sync Radarr configuration (download clients)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = [ "radarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "radarr";
        Group = "users";
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "radarr-sync-config.json" {
            download_clients = settings-sync.downloadClients;
          };
        in ''
          ${lib.getExe sync-settings} --config-file ${config-file}
        '';
      };
    };

    vpnNamespaces.wg = lib.mkIf vpn-enabled {
      enable = true;
      accessibleFrom = vpn-accessible-from;
      wireguardConfigFile = config.age.secrets.airvpn-wireguard.path;
      portMappings = [
        {
          from = config.site.apps.radarr.port;
          to = config.site.apps.radarr.port;
        }
      ];
    };

    services.caddy.virtualHosts."${radarr-domain}".extraConfig =
      reverse-proxy radarr-upstream;
  };
}