{ config, lib, pkgs }:

let
  inherit (lib)
    concatMapStringsSep
    filter
    getExe
    isAttrs
    isString
    mkOption
    pipe
    split
    toSentenceCase
    types;
in rec {
  mkArrLocalUrl = service:
    let
      port = config.site.apps.${service}.port;
      urlBase = config.services.${service}.settings.server.urlBase or "";
      host =
        if (config.site.apps.${service}.vpn.enable or false)
        then "192.168.15.1"
        else "127.0.0.1";
    in
      "http://${host}:${toString port}${urlBase}";

  toKebabSentenceCase = str:
    pipe str [
      (split "-")
      (filter isString)
      (concatMapStringsSep "-" toSentenceCase)
    ];

  secretFileType = types.submodule {
    options = {
      secret = mkOption {
        type = types.pathWith {
          inStore = false;
          absolute = true;
        };
        description = "Path to a file containing a secret value.";
      };
    };
  };

  arrCfgType = with types;
    attrsOf (oneOf [ str bool int secretFileType (listOf int) (listOf str) ]);

  arrDownloadClientConfigModule = service:
    let
      serviceName = toKebabSentenceCase service;
    in {
      freeformType = arrCfgType;
      options = {
        name = mkOption {
          type = types.str;
          description = "Unique download-client name used by ${serviceName}.";
        };
        implementation = mkOption {
          type = types.str;
          description = "Download-client implementation name used by ${serviceName}.";
        };
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether the download client should stay enabled in ${serviceName}.";
        };
        fields = mkOption {
          type = arrCfgType;
          default = { };
          description = "Per-field overrides to apply to the download-client schema.";
        };
      };
    };

  arrDownloadClientConfigType = service:
    types.submodule (arrDownloadClientConfigModule service);

  waitForArrService = args:
    waitForService (args // { url = args.url or mkArrLocalUrl args.service; });

  arrServiceNames = [
    "prowlarr"
    "radarr"
    "sonarr"
  ];

  waitForService = {
    service,
    url,
    max-secs-per-attempt ? 5,
    secs-between-attempts ? 5,
  }:
    getExe (pkgs.writeShellApplication {
      name = "wait-for-${service}";
      runtimeInputs = [ pkgs.curl ];
      text = ''
        while ! curl \
            --silent \
            --fail \
            --max-time ${toString max-secs-per-attempt} \
            --output /dev/null \
            '${url}'; do
          echo "Waiting for ${service} at '${url}'..."
          sleep ${toString secs-between-attempts}
        done
        echo "${service} is available at '${url}'"
      '';
    });
}