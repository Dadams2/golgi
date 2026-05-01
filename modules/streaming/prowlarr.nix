{ config, lib, pkgs, ... }:

let
  airvpn-secret-file = ../../secrets/airvpn-wireguard.age;
  prowlarr-domain =
    "${config.site.apps.prowlarr.subdomain}.${config.site.domain}";
  vpn-enabled = config.site.apps.prowlarr.vpn.enable;
  vpn-gateway-address = "192.168.15.1";
  prowlarr-upstream =
    if vpn-enabled
    then "${vpn-gateway-address}:${toString config.site.apps.prowlarr.port}"
    else ":${toString config.site.apps.prowlarr.port}";
  vpn-accessible-from =
    [ "127.0.0.1" ]
    ++ lib.optionals config.site.apps.prowlarr.vpn.exposeOnLAN [
      "192.168.1.0/24"
      "192.168.0.0/24"
    ]
    ++ config.site.apps.prowlarr.vpn.accessibleFrom;
  reverse-proxy = upstream: ''
    import auth
    reverse_proxy ${upstream}
  '';
in {
  assertions = [
    {
      assertion = (!vpn-enabled) || builtins.pathExists airvpn-secret-file;
      message = "Prowlarr VPN requires ../../secrets/airvpn-wireguard.age to exist.";
    }
  ];

  site.apps.prowlarr.enabled = true;

  age.secrets = lib.mkIf vpn-enabled {
    airvpn-wireguard = {
      owner = "root";
      group = "root";
      mode = "0400";
      file = airvpn-secret-file;
    };
  };

  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    home = config.site.apps.prowlarr.dir;
  };

  users.groups.prowlarr = { };

  systemd.tmpfiles.rules = [
    "d ${config.site.apps.prowlarr.dir} 0700 prowlarr root - -"
  ];

  services.prowlarr = {
    enable = true;
    package = pkgs.prowlarr;
    settings.server.port = config.site.apps.prowlarr.port;
    openFirewall = false;
  };

  systemd.services.prowlarr.environment.PROWLARR__AUTHENTICATIONMETHOD = "External";

  systemd.services.prowlarr.serviceConfig = {
    User = "prowlarr";
    Group = "prowlarr";
    ExecStart = lib.mkForce
      "${lib.getExe pkgs.prowlarr} -nobrowser -data=${config.site.apps.prowlarr.dir}";
    ReadWritePaths = [ config.site.apps.prowlarr.dir ];
  };

  systemd.services.prowlarr.vpnConfinement = lib.mkIf vpn-enabled {
    enable = true;
    vpnNamespace = "wg";
  };

  vpnNamespaces.wg = lib.mkIf vpn-enabled {
    enable = true;
    accessibleFrom = vpn-accessible-from;
    wireguardConfigFile = config.age.secrets.airvpn-wireguard.path;
    portMappings = [
      {
        from = config.site.apps.prowlarr.port;
        to = config.site.apps.prowlarr.port;
      }
    ];
  };

  services.caddy.virtualHosts."${prowlarr-domain}".extraConfig =
    reverse-proxy prowlarr-upstream;
}