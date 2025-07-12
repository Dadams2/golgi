{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 22 ];
  users.users.admin = {
    name = "admin";
    hashedPassword = "$6$xyz$gWnniaoEbqEkF6uAwHSCSKS0TOn3Fs1xNVthqD6S2F1TW177y9SlesYUHjdxhTcGC2ARUTVjImiq3xMvP6LBf1";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDvJOf3eKr8myTqabRJO/Mc/syqMn3FiSaIUKMkmKeF DAADAMS@distillation"
                                    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUTckgbAuZzXHuZZANrFsIXtm5L8P1AAtAm0wE7bELa dadams@david-x570aorusmaster"
                                  ];
  };
  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "@wheel" ]; # https://github.com/serokell/deploy-rs/issues/25
}
