{
  description = "Deployable system configurations";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils-plus.url = github:gytis-ivaskevicius/flake-utils-plus;
    agenix.url = "github:ryantm/agenix";
    crowdsec = {
      url = "git+https://codeberg.org/kampka/nix-flake-crowdsec.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    declarative-jellyfin.url = "github:Sveske-Juice/declarative-jellyfin";
    declarative-jellyfin.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, crowdsec, declarative-jellyfin, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      site-config = import ./site.nix;
      site-setup = {
        domain = "tecosaur.net";
        email = {
          server = "smtp.fastmail.com";
          username = "tec@tecosaur.net";
        };
        apps = {
          mealie.subdomain = "food";
          microbin = {
            title = "μPaste";
            subdomain = "pastes";
            short-subdomain = "p";
            user-group = "paste";
          };
          forgejo = {
            user-group = "forge";
          };
          headscale.enabled = true;
          # calibre-web.enabled = true;
          paperless.enabled = true;
          sftpgo.enabled = true;
          immich.enabled = true;
          jellyfin.enabled = true;
        };
      };
    in
    flake-utils-plus.lib.mkFlake {
      inherit self inputs modules;

      hosts.calcification.modules = with modules; [
          agenix.nixosModules.default
          auth
          caddy
          crowdsec.nixosModules.crowdsec
          crowdsec.nixosModules.crowdsec-firewall-bouncer
          crowdsec-setup
          homepage
          hardware-nas
          microbin
          site-config
          site-root
          system
          zsh
          {
            site = {
              domain = "dadams.org";
              server.host = "calcification";
              server.admin = {
                hashedPassword = "$6$xyz$gWnniaoEbqEkF6uAwHSCSKS0TOn3Fs1xNVthqD6S2F1TW177y9SlesYUHjdxhTcGC2ARUTVjImiq3xMvP6LBf1";
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDvJOf3eKr8myTqabRJO/Mc/syqMn3FiSaIUKMkmKeF DAADAMS@distillation"
                                      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUTckgbAuZzXHuZZANrFsIXtm5L8P1AAtAm0wE7bELa dadams@david-x570aorusmaster"
                                      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICo+Z6/pgjdomE8rHFT+EwlLaRIccFAFrBPw8mOzhfkp dadams@oxidation"
                                  ];
              };
            };
          }
      ];

      deploy.nodes = {
        calcification = {
          hostname = "192.168.188.93";
          fastConnection = false;
          profiles = {
            system = {
              sshUser = "admin";
              sshOpts = ["-o" "ControlMaster=no"];
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
