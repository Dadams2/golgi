let
  base = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHUTckgbAuZzXHuZZANrFsIXtm5L8P1AAtAm0wE7bELa dadams@david-x570aorusmaster";
  oxidation = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICo+Z6/pgjdomE8rHFT+EwlLaRIccFAFrBPw8mOzhfkp dadams@oxidation";
  calcification = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICrXlxKkyxDU7nC67Qt1r51SlPy4DqdSm1Zie2DIN4io root@calcification";
  mac = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGDvJOf3eKr8myTqabRJO/Mc/syqMn3FiSaIUKMkmKeF DAADAMS@distillation";
  all = [ base calcification mac oxidation ];
in
{
  "authelia-jwt.age".publicKeys = all;
  "authelia-oidc-hmac.age".publicKeys = all;
  "authelia-oidc-issuer.pem.age".publicKeys = all;
  "authelia-session.age".publicKeys = all;
  "authelia-storage.age".publicKeys = all;
  "cloudflare-api-env.age".publicKeys = all;
  "crowdsec-enroll-key.age".publicKeys = all;
  "fastmail.age".publicKeys = all;
  "headscale-oidc-secret.age".publicKeys = all;
  "headplane-env.age".publicKeys = all;
  "home-assistant-secrets.age".publicKeys = nbase;
  "immich-oidc-secret.age".publicKeys = all;
  "jellyfin-oidc-secret.age".publicKeys = nbase;
  "lldap-admin-password.age".publicKeys = all;
  "lldap-jwt.age".publicKeys = all;
  "lldap-key-seed.age".publicKeys = all;
  "mealie-credentials-env.age".publicKeys = all;
  "memos-oidc-secret.age".publicKeys = all;
  "ntfy-webpush-keys-env.age".publicKeys = all;
  "postgres-authelia.age".publicKeys = all;
  "postgres-forgejo.age".publicKeys = all;
  "paperless-oidc-secret.age".publicKeys = nbase;
  "paperless-admin-password.age".publicKeys = nbase;
  "sftpgo-env.age".publicKeys = all;
  "sftpgo-oidc-secret.age".publicKeys = all;
  "tailscale-preauth.age".publicKeys = all;
  "warracker-oidc-secret.age".publicKeys = all;
  "vikunja-oidc.age".publicKeys = all;
}
