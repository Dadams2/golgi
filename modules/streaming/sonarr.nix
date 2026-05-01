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
  sonarr-domain =
    "${config.site.apps.sonarr.subdomain}.${config.site.domain}";
  vpn-enabled = config.site.apps.sonarr.vpn.enable;
  vpn-gateway-address = "192.168.15.1";
  sonarr-upstream =
    if vpn-enabled
    then "${vpn-gateway-address}:${toString config.site.apps.sonarr.port}"
    else ":${toString config.site.apps.sonarr.port}";
  settings-sync = config.site.apps.sonarr.settings-sync;
  sync-settings = writePython3Bin "nixarr-sync-sonarr-settings" {
    libraries = [ arr-sync-py ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./sonarr-sync-settings.py);
  wantedServices = [ "sonarr-api.service" ];
  vpn-accessible-from =
    [ "127.0.0.1" ]
    ++ lib.optionals config.site.apps.sonarr.vpn.exposeOnLAN [
      "192.168.1.0/24"
      "192.168.0.0/24"
    ]
    ++ config.site.apps.sonarr.vpn.accessibleFrom;
  reverse-proxy = upstream: ''
    import auth
    reverse_proxy ${upstream}
  '';
in {
  options.site.apps.sonarr.settings-sync = {
    downloadClients = lib.mkOption {
      type = lib.types.listOf (arrDownloadClientConfigType "sonarr");
      default = [ ];
      description = "Additional Sonarr download clients to reconcile automatically.";
    };
    transmission = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically keep Transmission configured as a Sonarr download client.";
      };
      config = lib.mkOption {
        type = lib.types.submodule [
          (arrDownloadClientConfigModule "sonarr")
          {
            config = {
              name = "Transmission";
              implementation = "Transmission";
              enable = true;
              fields = {
                # We can use localhost even if Sonarr or Transmission are in
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
        description = "Default Sonarr download-client configuration for Transmission.";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = (!vpn-enabled) || builtins.pathExists airvpn-secret-file;
        message = "Sonarr VPN requires ../../secrets/airvpn-wireguard.age to exist.";
      }
      {
        assertion = (!settings-sync.transmission.enable) || config.site.apps.transmission.enabled;
        message = "Sonarr Transmission sync requires the Transmission module to be enabled.";
      }
    ];

    site.apps.sonarr.settings-sync.downloadClients = lib.mkIf settings-sync.transmission.enable [
      settings-sync.transmission.config
    ];

    site.apps.sonarr.enabled = true;

    age.secrets = lib.mkIf vpn-enabled {
      airvpn-wireguard = {
        owner = "root";
        group = "root";
        mode = "0400";
        file = airvpn-secret-file;
      };
    };

    users.users.sonarr = {
      isSystemUser = true;
      group = "users";
      home = config.site.apps.sonarr.dir;
      extraGroups = [ "sonarr-api" ];
    };

    systemd.tmpfiles.rules = [
      "d ${config.site.apps.sonarr.dir} 0750 sonarr users - -"
    ];

    services.sonarr = {
      enable = true;
      package = pkgs.sonarr;
      user = "sonarr";
      group = "users";
      settings.server.port = config.site.apps.sonarr.port;
      openFirewall = false;
      dataDir = config.site.apps.sonarr.dir;
    };

    systemd.services.sonarr.environment.SONARR__AUTHENTICATIONMETHOD = "External";

    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";

    systemd.services.sonarr.vpnConfinement = lib.mkIf vpn-enabled {
      enable = true;
      vpnNamespace = "wg";
    };

    systemd.services.sonarr-sync-config = {
      description = ''
        Sync Sonarr configuration (download clients)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = [ "sonarr.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "sonarr";
        Group = "users";
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "sonarr-sync-config.json" {
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
          from = config.site.apps.sonarr.port;
          to = config.site.apps.sonarr.port;
        }
      ];
    };

    services.caddy.virtualHosts."${sonarr-domain}".extraConfig =
      reverse-proxy sonarr-upstream;
  };
}