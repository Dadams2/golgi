{
  description = "Deployable system configurations";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
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
            forgejo
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
        nucleus.modules = with modules; [
          declarative-jellyfin.nixosModules.default
          hardware-nas
          home-assistant
          immich
          llm
          lyrion
          paperless
          scrutiny
          sftpgo
          speedtest
          streaming
          warracker
        ];
      };
      global-enabled-apps = (nixpkgs.lib.concatMapAttrs (machine: setup:
        (nixpkgs.lib.foldlAttrs
          (acc: app: conf:
            if conf.enabled then
              acc // { "${app}" = {enabled = true; host = machine; }; }
            else acc)
          { }
          (nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [ flake-utils-plus.nixosModules.autoGenFromInputs ] ++
                      core-modules ++ setup.modules ++
                      [ { site.domain = "_"; } ];
          }).config.site.apps))
        machines);
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
