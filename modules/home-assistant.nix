{ config, lib, pkgs, ... }:

let
  ha-domain = "${config.site.apps.home-assistant.subdomain}.${config.site.domain}";
  ha-oidc-domain = "login-${config.site.apps.home-assistant.subdomain}.${config.site.domain}";
  authelia-domain = "${config.site.apps.authelia.subdomain}.${config.site.domain}";
  ha-package = pkgs.home-assistant.override {
    packageOverrides = self: super: {
      radios = super.radios.overridePythonAttrs (oldAttrs: {
        pythonRelaxDeps = (oldAttrs.pythonRelaxDeps or [ ]) ++ [ "pycountry" ];
      });
    };
  };
  hax-bambu = ha-package.python.pkgs.callPackage ../packages/ha-bambu.nix { };
  hax-bom = ha-package.python.pkgs.callPackage ../packages/ha-bom.nix { };
  hax-vzug = ha-package.python.pkgs.callPackage ../packages/ha-vzug.nix { };
in {
  site.apps.home-assistant.enabled = true;
  site.apps.home-assistant.groups.primary = lib.mkDefault "home-assistant";

  age.secrets.home-assistant-secrets = {
    owner = "hass";
    group = "users";
    file = ../secrets/home-assistant-secrets.age;
    path = "/var/lib/hass/secrets.yaml";
  };

  environment.etc."home-assistant/secrets.yaml".source =
    config.age.secrets.home-assistant-secrets.path;

  services.home-assistant = {
    enable = true;
    package = ha-package;
    extraComponents = [
      "apple_tv"
      "aussie_broadband"
      "apollo_automation"
      "brother"
      "camera"
      "cast"
      "esphome"
      "google_translate"
      "immich"
      "linkplay"
      "matter"
      "mealie"
      "met"
      "mikrotik"
      "music_assistant"
      "nanoleaf"
      "ntfy"
      "radio_browser"
      "stream"
      "thread"
      "tuya"
      "wake_on_lan"
      "zeroconf"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      adaptive_lighting
      auth_oidc
      hax-bambu
      hax-bom
      hax-vzug
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      mushroom
      mini-graph-card
      mini-media-player
      weather-card
      weather-chart-card
      clock-weather-card
      hourly-weather
      universal-remote-card
    ];
    config = {
      http = {
        server_port = config.site.apps.home-assistant.port;
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" "::1" ];
      };
      auth_oidc = {
        client_id = "home-assistant";
        discovery_url = "https://${authelia-domain}/.well-known/openid-configuration";
        display_name = "Authelia";
        client_secret = "!secret oidc_client_secret";
        roles = {
          user = config.site.apps.home-assistant.groups.primary;
        } // lib.optionalAttrs (config.site.apps.home-assistant.groups.admin != null) {
          admin = config.site.apps.home-assistant.groups.admin;
        };
      };
      default_config = {};
      script = "!include scripts.yaml";
      scene = "!include scenes.yaml";
      automation = "!include automations.yaml";
      homeassistant = {
        external_url = "https://${ha-domain}";
        time_zone = "!secret time_zone";
        media_dirs = {
          local = "/data/media";
        };
      };
      zone = [
        {
          name = "Home";
          icon = "mdi:home";
          latitude = "!secret home_latitude";
          longitude = "!secret home_longitude";
          radius = 40;
        }
      ];
    };
  };

  services.matter-server = {
    enable = true;
  };

  services.caddy.virtualHosts."${ha-domain}".extraConfig =
    ''
    reverse_proxy :${toString config.site.apps.home-assistant.port}
  '';

  services.caddy.virtualHosts."${ha-oidc-domain}".extraConfig =
    ''
    redir https://${ha-domain}/auth/oidc/redirect 302
  '';

  systemd.services.home-assistant.preStart = lib.mkAfter ''
    ensure_yaml_file() {
      local path="$1"
      local initial_contents="$2"

      if [ ! -s "$path" ]; then
        printf '%s\n' "$initial_contents" > "$path"
      fi
    }

    config_dir="${config.services.home-assistant.configDir}"
    ensure_yaml_file "$config_dir/automations.yaml" '[]'
    ensure_yaml_file "$config_dir/scripts.yaml" '{}'
    ensure_yaml_file "$config_dir/scenes.yaml" '[]'
  '';
}
