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
    deploy-rs = {
      url = github:serokell/deploy-rs;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig.sandbox = "relaxed";

  outputs = inputs@{ self, nixpkgs, flake-utils-plus, agenix, crowdsec, ... }:
    let
      modules = flake-utils-plus.lib.exportModules (
        nixpkgs.lib.mapAttrsToList (name: value: ./modules/${name}) (builtins.readDir ./modules)
      );
      site-config = import ./site.nix;
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
              server = {
                host = "calcification";
                authoritative = true;
                ipv6 = "2401:d006:b206:4700:caff:bfff:fe05:efc2";
                ipversions = "ipv6";
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
