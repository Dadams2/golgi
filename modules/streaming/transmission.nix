{ config, lib, pkgs, ... }:

let
  airvpn-secret-file = ../../secrets/airvpn-wireguard.age;
  transmission-domain =
    "${config.site.apps.transmission.subdomain}.${config.site.domain}";
  download-dir = "/data/media/downloads";
  incomplete-dir = "${download-dir}/.incomplete";
  extra-dirs = [ "/data/media" ];
  vpn-enabled = config.site.apps.transmission.vpn.enable;
  vpn-gateway-address = "192.168.15.1";
  transmission-upstream =
    if vpn-enabled
    then "${vpn-gateway-address}:${toString config.site.apps.transmission.port}"
    else ":${toString config.site.apps.transmission.port}";
  rpc-whitelist = lib.concatStringsSep "," (
    [ "127.0.0.1" ]
    ++ (if vpn-enabled then [ "192.168.*" ] else [ "192.168.1.*" ])
    ++ [ "100.*.*.*" ]
  );
  rpc-host-whitelist = lib.concatStringsSep "," [
    "localhost"
    "127.0.0.1"
    "192.168.1.*"
    transmission-domain
    "100.*.*.*"
    "nas.lan"
    "${config.site.server.host}.${config.site.apps.headscale.magicdns-subdomain}.${config.site.domain}"
  ];
  vpn-accessible-from =
    [ "127.0.0.1" ]
    ++ lib.optionals config.site.apps.transmission.vpn.exposeOnLAN [
      "192.168.1.0/24"
      "192.168.0.0/24"
    ]
    ++ config.site.apps.transmission.vpn.accessibleFrom;
  reverse-proxy = upstream: ''
    import auth
    reverse_proxy ${upstream}
  '';
in {
  assertions = [
    {
      assertion = (!vpn-enabled) || builtins.pathExists airvpn-secret-file;
      message = "Transmission VPN requires ../../secrets/airvpn-wireguard.age to exist.";
    }
  ];

  site.apps.transmission.enabled = true;

  age.secrets = lib.mkIf vpn-enabled {
    airvpn-wireguard = {
      owner = "root";
      group = "root";
      mode = "0400";
      file = airvpn-secret-file;
    };
  };

  services.transmission = {
    enable = true;
    group = "users";
    package = pkgs.transmission_4;
    openRPCPort = !vpn-enabled;
    webHome = pkgs.flood-for-transmission;
    settings = {
      rpc-bind-address = if vpn-enabled then vpn-gateway-address else "0.0.0.0";
      rpc-port = config.site.apps.transmission.port;
      rpc-whitelist = rpc-whitelist;
      rpc-host-whitelist-enabled = true;
      rpc-host-whitelist = rpc-host-whitelist;
      rpc-authentication-required = false;
      ratio-limit-enabled = true;
      ratio-limit = 2;
      peer-port = config.site.apps.transmission.peer-port;
      download-dir = download-dir;
      incomplete-dir = incomplete-dir;
      rename-partial-files = true;
      umask = "002";
    };
  };

  systemd.services.transmission.serviceConfig = {
    UMask = lib.mkForce "0007";
    BindPaths = extra-dirs;
  };

  systemd.services.transmission.vpnConfinement = lib.mkIf vpn-enabled {
    enable = true;
    vpnNamespace = "wg";
  };

  vpnNamespaces.wg = lib.mkIf vpn-enabled {
    enable = true;
    accessibleFrom = vpn-accessible-from;
    wireguardConfigFile = config.age.secrets.airvpn-wireguard.path;
    portMappings = [
      {
        from = config.site.apps.transmission.port;
        to = config.site.apps.transmission.port;
      }
    ];
    openVPNPorts = [
      {
        port = config.site.apps.transmission.peer-port;
        protocol = "both";
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${download-dir} 0775 ${config.services.transmission.user} users - -"
    "d ${incomplete-dir} 0775 ${config.services.transmission.user} users - -"
  ];

  services.caddy.virtualHosts."${transmission-domain}".extraConfig =
    reverse-proxy transmission-upstream;
}
