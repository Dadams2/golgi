{ config, lib, options, ... }:

let
  has-nixarr-options = options ? nixarr;
  airvpn-secret-file = ../../secrets/airvpn-wireguard.age;
  has-airvpn-secret = builtins.pathExists airvpn-secret-file;
  transmission-domain = "${config.site.apps.transmission.subdomain}.${config.site.domain}";
  radarr-domain = "${config.site.apps.radarr.subdomain}.${config.site.domain}";
  sonarr-domain = "${config.site.apps.sonarr.subdomain}.${config.site.domain}";
  prowlarr-domain = "${config.site.apps.prowlarr.subdomain}.${config.site.domain}";
  bazarr-domain = "${config.site.apps.bazarr.subdomain}.${config.site.domain}";
  download-dir = "/data/media/downloads";
  incomplete-dir = "${download-dir}/.incomplete";
  transmission-upstream =
    if has-airvpn-secret
    then "192.168.15.1:${toString config.site.apps.transmission.port}"
    else ":${toString config.site.apps.transmission.port}";
  reverse-proxy = upstream: ''
    import auth
    reverse_proxy ${upstream}
  '';
in {
  config = lib.mkIf has-nixarr-options {
    site.apps = {
      bazarr.enabled = true;
      prowlarr.enabled = true;
      radarr.enabled = true;
      sonarr.enabled = true;
      transmission.enabled = true;
    };

    age.secrets = lib.mkIf has-airvpn-secret {
      airvpn-wireguard = {
        owner = "root";
        group = "root";
        mode = "0400";
        file = airvpn-secret-file;
      };
    };

    nixarr = {
      enable = true;
      mediaDir = "/data/media";
      mediaUsers = [ config.services.jellyfin.user ];

      vpn = lib.mkIf has-airvpn-secret {
        enable = true;
        accessibleFrom = [ "100.64.0.0/10" ];
        wgConf = config.age.secrets.airvpn-wireguard.path;
      };

      bazarr = {
        enable = true;
        openFirewall = false;
        port = config.site.apps.bazarr.port;
        
        # Automatically configure Sonarr and Radarr connections in Bazarr
        settings-sync = {
          sonarr = {
            enable = true;
            config = {
              sync_only_monitored_series = true;
              sync_only_monitored_episodes = true;
            };
          };
          radarr = {
            enable = true;
            config = {
              sync_only_monitored_movies = true;
            };
          };
        };
      };

      prowlarr = {
        enable = true;
        openFirewall = false;
        port = config.site.apps.prowlarr.port;
        
        # Automatically sync enabled Nixarr apps (Sonarr/Radarr) to Prowlarr
        settings-sync = {
          enable-nixarr-apps = true;
        };
      };

      radarr = {
        enable = true;
        openFirewall = false;
        port = config.site.apps.radarr.port;
        
        # Automatically configure Transmission as a download client
        settings-sync = {
          transmission = {
            enable = true;
            # ugly hack to force the host to be the VPN gateway if the AirVPN secret is present, otherwise default to localhost
            config.fields.host = if has-airvpn-secret then lib.mkForce "192.168.15.1" else "localhost";
          };
        };
      };

      sonarr = {
        enable = true;
        openFirewall = false;
        port = config.site.apps.sonarr.port;
        
        # Automatically configure Transmission as a download client
        settings-sync = {
          transmission = {
            enable = true;
            config.fields.host = if has-airvpn-secret then lib.mkForce "192.168.15.1" else "localhost";
          };
        };
      };

      transmission = {
        enable = true;
        flood.enable = true;
        openFirewall = false;
        peerPort = config.site.apps.transmission.peer-port;
        uiPort = config.site.apps.transmission.port;
        vpn.enable = has-airvpn-secret;
        extraAllowedIps = [ "100.*.*.*" ];
        extraSettings = {
          download-dir = download-dir;
          incomplete-dir = incomplete-dir;
          incomplete-dir-enabled = true;
          rename-partial-files = true;
          ratio-limit-enabled = true;
          ratio-limit = 2;
          rpc-bind-address = "0.0.0.0";
          rpc-port = config.site.apps.transmission.port;
          rpc-whitelist = "127.0.0.1,192.168.1.*,192.168.15.*,100.*.*.*";
          rpc-host-whitelist-enabled = true;
          rpc-host-whitelist = lib.concatStringsSep "," [
            "localhost"
            "127.0.0.1"
            "192.168.1.*"
            "192.168.15.*"
            transmission-domain
            "100.*.*.*"
            "nas.lan"
            "${config.site.server.host}.${config.site.apps.headscale.magicdns-subdomain}.${config.site.domain}"
          ];
          rpc-authentication-required = false;
          umask = "002";
          watch-dir-enabled = false;
        };
      };
    };

    systemd.services.transmission.serviceConfig = {
      UMask = lib.mkForce "0007";
      BindPaths = [ "/data/media" ];
    };

    systemd.tmpfiles.rules = [
      "d /data/.state/nixarr/radarr 0700 ${config.util-nixarr.globals.radarr.user} root - -"
      "d /data/.state/nixarr/sonarr 0700 ${config.util-nixarr.globals.sonarr.user} root - -"
      "z /data/.state/nixarr/radarr 0700 ${config.util-nixarr.globals.radarr.user} root - -"
      "z /data/.state/nixarr/sonarr 0700 ${config.util-nixarr.globals.sonarr.user} root - -"
      "d ${download-dir} 0775 ${config.util-nixarr.globals.transmission.user} ${config.util-nixarr.globals.transmission.group} - -"
      "d ${incomplete-dir} 0775 ${config.util-nixarr.globals.transmission.user} ${config.util-nixarr.globals.transmission.group} - -"
    ];

    services.prowlarr.settings.auth.required = "DisabledForLocalAddresses";
    services.radarr.settings.auth.required = "DisabledForLocalAddresses";
    services.sonarr.settings.auth.required = "DisabledForLocalAddresses";

    # Add Flaresolverr as a standard NixOS service to solve captchas for Prowlarr
    services.flaresolverr = {
      enable = true;
      port = 8191;
    };

    services.nginx = lib.mkIf has-airvpn-secret {
      enable = lib.mkForce false;
    };

    services.caddy.virtualHosts."${bazarr-domain}".extraConfig =
      reverse-proxy ":${toString config.site.apps.bazarr.port}";

    services.caddy.virtualHosts."${prowlarr-domain}".extraConfig =
      reverse-proxy ":${toString config.site.apps.prowlarr.port}";

    services.caddy.virtualHosts."${radarr-domain}".extraConfig =
      reverse-proxy ":${toString config.site.apps.radarr.port}";

    services.caddy.virtualHosts."${sonarr-domain}".extraConfig =
      reverse-proxy ":${toString config.site.apps.sonarr.port}";

    services.caddy.virtualHosts."${transmission-domain}".extraConfig =
      reverse-proxy transmission-upstream;
  };
}