{ config, lib, pkgs, ... }:

let
  inherit (lib)
    genAttrs
    getExe'
    mkIf
    mkMerge;
  inherit (pkgs.writers) writeJSON;

  arr-sync-lib = import ./arr-sync-lib.nix { inherit config lib pkgs; };
  inherit (arr-sync-lib)
    arrServiceNames
    mkArrLocalUrl
    waitForArrService;

  enabled-services = builtins.filter (service: config.site.apps.${service}.enabled) arrServiceNames;
  state-dir = "/data/.state/arr-sync";
  service-config-file = genAttrs arrServiceNames (service: "${config.site.apps.${service}.dir}/config.xml");
  xq = getExe' pkgs.yq "xq";
  local-config = genAttrs enabled-services (service: {
    base_url = mkArrLocalUrl service;
    api_key_file = "${state-dir}/secrets/${service}.api-key";
  });

  print-service-api-key = genAttrs arrServiceNames (service:
    pkgs.writeShellScript "print-${service}-api-key" ''
      ${xq} -r .Config.ApiKey '${service-config-file.${service}}'
    '');

  mk-api-service = service: {
    description = "Wait for ${service} API and extract key";
    after = [ "${service}.service" ];
    requires = [ "${service}.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Group = "${service}-api";
      UMask = "0027";

      ExecStartPre = [ (waitForArrService { inherit service; }) ];
      ExecStart = pkgs.writeShellScript "extract-${service}-api-key" ''
        ${print-service-api-key.${service}} > '${state-dir}/secrets/${service}.api-key'
      '';
    };
  };
in {
  config = mkIf (enabled-services != [ ]) {
    users.groups = mkMerge (
      builtins.map (service: { "${service}-api" = { }; }) enabled-services
    );

    systemd.services = mkMerge (
      builtins.map (service: { "${service}-api" = mk-api-service service; }) enabled-services
    );

    environment.etc."nixarr/nixarr-py.json".source =
      writeJSON "nixarr-py.json" local-config;

    systemd.tmpfiles.rules = [
      "d ${state-dir} 0755 root root - -"
      "d ${state-dir}/secrets 0701 root root - -"
    ];
  };
}