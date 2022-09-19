{ config, pkgs, inputs, ... }:

{
  time.timeZone = "UTC";
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
  };
  services.journald.extraConfig = ''
SystemMaxUse=1G
SystemMaxFileSize=100M
MaxFileSec=1day
MaxRetentionSec=2months
''; # Limit journal accumulation
  system.stateVersion = "22.05";

  nix = {
    # Currently needed for flake support, might not be needed in the future
    package = pkgs.nixUnstable;

    extraOptions = ''
      experimental-features = nix-command flakes
    '';

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    settings.auto-optimise-store = true;

    # from flake-utils-plus
    # Sets NIX_PATH to follow this flake's nix inputs
    # So legacy nix-channel is not needed
    generateNixPathFromInputs = true;
    linkInputs = true;
    # Pin our nixpkgs flake to the one used to build the system
    generateRegistryFromInputs = true;
  };

  # Set the system revision to the flake revision
  # You can query this value with: $ nix-info -m
  system.configurationRevision = (if inputs.self ? rev then inputs.self.rev else null);
}
