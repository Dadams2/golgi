{
  description = "Deployable system configurations";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    # Pinned: declarative-jellyfin doesn't support Jellyfin 12.4 yet
    nixpkgs-jellyfin.url = "github:NixOS/nixpkgs/1559d3daa3ecc813a650b79375ea61b6741b8746";
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    agenix.url = "github:ryantm/agenix";
    declarative-jellyfin.url = "github:Sveske-Juice/declarative-jellyfin";
    declarative-jellyfin.inputs.nixpkgs.follows = "nixpkgs";
    nixarr = {
      url = "github:rasmus-kirk/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, declarative-jellyfin, nixarr, ... }:
    let
      site-config = import ./site.nix;
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      core-modules = with modules; [
        agenix.nixosModules.default
        beszel-agent
        caddy
        dns-pooler
        site-config
        system
        tailscale
        zsh
      ];
      machines = {
        golgi = {
          server = {
            authoritative = true;
            ipv6 = "2a01:4ff:f0:cc83";
          };
          modules = with modules; [
            auth
            beszel-hub
            fava
            hardware-hetzner
            headscale
            homepage
            ntfy
            mealie
            memos
            microbin
            site-root
            syncthing
            uptime
            vikunja
          ];
        };
        nucleus = {
          apps.llm.proxy = [ "tranquillity.lan:5521" ];
          modules = with modules; [
            data-mounts
            declarative-jellyfin.nixosModules.default
            hardware-nas
            home-assistant
            dawarich
            forgejo
            immich
            llm
            lyrion
            paperless
            scrobbler
            scrutiny
            sftpgo
            site-root
            speedtest
            storyteller
            streaming
            tandoor
            trek
            warracker
          ];
        };
      };
      # Every machine evaluated with its real site settings, short of what is
      # computed from all of them, for the facts one host's configuration
      # needs about the others.
      machine-systems = nixpkgs.lib.mapAttrs
        (name: setup: (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ flake-utils-plus.nixosModules.autoGenFromInputs ] ++
                    core-modules ++ setup.modules ++
                    [ { site = machine-site name setup; } ];
        }))
        machines;
      global-enabled-apps = nixpkgs.lib.concatMapAttrs (machine: sys:
        (nixpkgs.lib.foldlAttrs
          (acc: app: conf:
            if conf.enabled then
              acc // { "${app}" = {
                         enabled = true;
                         host = machine;
                         serviceConfig = if conf.service == null then { } else
                           sys.config.systemd.services."${conf.service}".serviceConfig;
                       }; }
            else acc)
          { }
          sys.config.site.apps))
        machine-systems;
      # The names each machine's Caddy serves, relative to the domain ("@" the
      # apex): a virtual host key may list several addresses, with a scheme or
      # port, and only those under the site domain are ours.
      global-served-names = nixpkgs.lib.mapAttrs (_: sys:
        let
          inherit (nixpkgs) lib;
          domain = site-setup.domain;
          relative = address:
            let host = lib.head (lib.splitString ":"
                  (lib.removePrefix "https://" (lib.removePrefix "http://" address)));
            in if host == domain then [ "@" ]
               else lib.optional (lib.hasSuffix ".${domain}" host) (lib.removeSuffix ".${domain}" host);
          addresses = key: lib.filter (a: a != "")
            (lib.splitString " " (lib.replaceStrings [ "," ] [ " " ] key));
        in lib.unique (lib.concatMap (key: lib.concatMap relative (addresses key))
          (lib.attrNames sys.config.services.caddy.virtualHosts)))
        machine-systems;
      # One machine's site settings, everything but what is computed across
      # machines (global-enabled-apps, dns.served).
      machine-site = name: setup: nixpkgs.lib.recursiveUpdate site-setup {
        hosts = builtins.attrNames machines;
        server = (setup.server or { }) // { host = name; };
        apps = nixpkgs.lib.recursiveUpdate site-setup.apps (setup.apps or { });
      };
      site-setup = {
        domain = "dadams.org";
        email = {
          server = "smtp.fastmail.com";
          username = "david@dadams2.com";
        };
        accent = {
          primary = "#33c1fbff";
          secondary = "#3340fbff";
        };
        apps = {
          mealie.subdomain = "food";
          memos.groups.extra = [ "family" ];
          microbin = {
            title = "μPaste";
            subdomain = "pastes";
            short-subdomain = "p";
            groups.primary = "paste";
          };
          forgejo = {
            user-group = "forge";
            site-name = "Code by dadams";
            site-description = "The personal Forgejo instance of dadams";
            # default-user-redirect = "dadams";
          };

          # headscale.enabled = true;
          # calibre-web.enabled = true;
          # paperless.enabled = true;
          # sftpgo.enabled = true;
          immich.enabled = true;
          jellyfin.enabled = true;
        };
      };
    in flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts.calcification.modules = with modules; [
          agenix.nixosModules.default
          auth
          caddy
          declarative-jellyfin.nixosModules.default
          nixarr.nixosModules.default
          forgejo
          home-assistant
          homepage
          hardware-nas
          immich
          streaming
          memos
          microbin
          scrutiny
          site-config
          site-root
          system
          tailscale
          tandoor
          uptime
          zsh
          {
            site = {
              domain = "dadams.org";
              email = {
                server = "smtp.fastmail.com";
                username = "david@dadams2.com";
              };
              server = {
                host = "calcification";
                authoritative = true;
                ipv6 = "2401:d006:b206:4700:caff:bfff:fe05:efc2";
                admin = {
                  hashedPassword = "$6$xyz$gWnniaoEbqEkF6uAwHSCSKS0TOn3Fs1xNVthqD6S2F1TW177y9SlesYUHjdxhTcGC2ARUTVjImiq3xMvP6LBf1";
                  authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDvJOf3eKr8myTqabRJO/Mc/syqMn3FiSaIUKMkmKeF DAADAMS@distillation"
                                        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUTckgbAuZzXHuZZANrFsIXtm5L8P1AAtAm0wE7bELa dadams@david-x570aorusmaster"
                                        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICo+Z6/pgjdomE8rHFT+EwlLaRIccFAFrBPw8mOzhfkp dadams@oxidation"
                                    ];
                };
                ipversions = ["ipv4" "ipv6"];
              };
            };
          }
      ];

      deploy.nodes = {
        calcification = {
          hostname = "calcification";
          fastConnection = false;
          profiles = {
            system = {
              sshUser = "admin";
              sshOpts = ["-S" "none"];
              path =
                inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.calcification;
              user = "root";
            };
          };
        };
      };

      outputsBuilder = (channels: {
        devShells.default = channels.nixpkgs.mkShell {
          name = "deploy";
          buildInputs = with channels.nixpkgs; [
            nixVersions.latest
            inputs.deploy-rs.packages.${system}.default
          ];
        };
      });

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
    };
}
