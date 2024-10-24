{ config, lib, pkgs, ... }:

let
  forgejo-user = "git";
  forgejo-domain = "code.${config.globals.domain}";
  blog-domain = "blog.${config.globals.domain}";
  # theming
  catppuccinThemes = pkgs.fetchzip {
    url = "https://github.com/catppuccin/gitea/releases/download/v0.4.1/catppuccin-gitea.tar.gz";
    sha256 = "sha256-14XqO1ZhhPS7VDBSzqW55kh6n5cFZGZmvRCtMEh8JPI=";
    stripRoot = false;
  };
  catppuccinAutoThemes = pkgs.runCommand "catppuccin-auto-themes" { buildInputs = [ pkgs.coreutils ]; } ''
    mkdir -p $out
    for f in ${catppuccinThemes}/theme-catppuccin-latte-*.css; do
      f_frappe="$(echo "$f" | sed 's/latte/frappe/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_frappe")" "$(cat "$f")" > "$out/$(basename "$f_frappe")"
      f_macchiato="$(echo "$f" | sed 's/latte/macchiato/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_macchiato")" "$(cat "$f")" > "$out/$(basename "$f_macchiato")"
      f_mocha="$(echo "$f" | sed 's/latte/mocha/')"
      printf "@media (prefers-color-scheme: dark) {\n%s\n}\n\n@media (prefers-color-scheme: light){\n%s\n}" \
        "$(cat "$f_mocha")" "$(cat "$f")" > "$out/$(basename "$f_mocha")"
    done
  '';
in {
  age.secrets.postgres-forgejo = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/postgres-forgejo.age;
  };

  age.secrets.fastmail = {
    owner = forgejo-user;
    group = "users";
    file = ../../secrets/fastmail.age;
  };

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    user = forgejo-user;
    group = forgejo-user;
    stateDir = "/var/lib/forgejo";
    database = {
      type = "postgres";
      name = forgejo-user;
      user = forgejo-user;
      passwordFile = config.age.secrets.postgres-forgejo.path;
    };
    lfs.enable = true;
    secrets = {
      mailer.PASSWD = config.age.secrets.fastmail.path;
    };
    settings = {
      DEFAULT.APP_NAME = "Code by TEC";
      server = {
        DOMAIN = "${forgejo-domain}";
        ROOT_URL = "https://${forgejo-domain}";
        HTTP_ADDRESS = "0.0.0.0";
        HTTP_PORT = 3000;
      };
      mailer = {
        ENABLED = true;
        PROTOCOL = "smtp+startls";
        FROM = "forgejo@${forgejo-domain}";
        USER = "tec@tecosaur.net";
        SMTP_ADDR = "smtp.fastmail.com:587";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = false;
        DISABLE_REGISTRATION = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
      };
      openid = {
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
        WHITELISTED_URIS = "auth.tecosaur.net";
      };
      oauth2_client = {
        ENABLE_AUTO_REGISTRATION = true;
        ACCOUNT_LINKING = "auto";
        OPENID_CONNECT_SCOPES = "openid email profile groups";
        USERNAME = "userid";
      };
      indexer = {
        REPO_INDEXER_ENABLED = true;
        REPO_INDEXER_EXCLUDE = "**.pdf, **.png, **.jpeg, **.jpm, **.svg, **.webm";
      };
      repository = {
        DEFAULT_PRIVATE = "public";
        DEFAULT_PUSH_CREATE_PRIVATE = false;
        ENABLE_PUSH_CREATE_USER = true;
        PREFERRED_LICENSES = "GPL-3.0-or-later,MIT";
        DEFAULT_REPO_UNITS = "repo.code,repo.issues,repo.pulls";
      };
      # "repository.mimetype_mapping" = {
      #   ".org" = "text/org";
      # };
      # actions = {
      #   ENABLED = true;
      # };
      ui = {
        GRAPH_MAX_COMMIT_NUM = 200;
        THEME_COLOR_META_TAG = "#609926";
        DEFAULT_THEME = "gitea-auto";
        THEMES = let
          builtinThemes = [
            "forgejo-auto"
            "forgejo-light"
            "forgejo-dark"
            "gitea-auto"
            "gitea-light"
            "gitea-dark"
            "forgejo-auto-deuteranopia-protanopia"
            "forgejo-light-deuteranopia-protanopia"
            "forgejo-dark-deuteranopia-protanopia"
            "forgejo-auto-tritanopia"
            "forgejo-light-tritanopia"
            "forgejo-dark-tritanopia"
          ];
        in (builtins.concatStringsSep "," (
          builtinThemes
          ++ (map (name: lib.removePrefix "theme-" (lib.removeSuffix ".css" name)) (
            builtins.attrNames (builtins.readDir catppuccinAutoThemes)
          ))
        ));
      };
      "ui.meta" = {
        DESCRIPTION = "The personal forge of TEC";
      };
      federation = {
        ENABLED = true;
      };
    };
  };

  users.users.${forgejo-user} = {
    home = config.services.forgejo.stateDir;
    useDefaultShell = true;
    group = forgejo-user;
    isSystemUser = true;
  };

  users.groups.${forgejo-user} = {};

  systemd.tmpfiles.rules = [
    "L+ ${config.services.forgejo.stateDir}/custom/templates/home.tmpl - - - - ${./template-home.tmpl}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/tree-greentea-themed.svg - - - - ${./images/tree-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/logo.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.svg - - - - ${./images/forgejo-icon-greentea-themed.svg}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/favicon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/apple-touch-icon.png - - - - ${./images/forgejo-icon-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/img/avatar_default.png - - - - ${./images/forgejo-square-greentea-themed.png}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/assets/css - - - - ${catppuccinAutoThemes}"
    "L+ ${config.services.forgejo.stateDir}/custom/public/robots.txt - - - - ${./robots.txt}"
  ];

  services.authelia.instances.main.settings = {
    identity_providers.oidc = {
      authorization_policies.forgejo = {
        default_policy = "one_factor";
        rules = [
          {
            policy = "two_factor";
            subject = [ [ "group:admin" "group:forge" ] ];
          }
        ];
      };
      clients = [
        {
          client_id = "forgejo";
          client_name = "Forgejo";
          client_secret = "$argon2id$v=19$m=65536,t=3,p=4$fRdkE7fHqAPkVQYXn1Zksw$O6WQ4fsNoN/0vzOK4hT1oreVPyFoVcK2hOIFx3axe/A";
          authorization_policy = "forgejo";
          public = false;
          consent_mode = "implicit";
          redirect_uris = [ "https://${forgejo-domain}/user/oauth2/authelia/callback" ];
          scopes = [ "openid" "email" "profile" "groups" ];
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];
    };
  };

  services.caddy.virtualHosts."git.${config.globals.domain}".extraConfig =
    "redir https://${forgejo-domain}{uri} 301";

  services.caddy.virtualHosts."${forgejo-domain}".extraConfig =
    ''
    @not_tec {
        not path /tec/*
        not header Cookie *caddy_tec_redirect=true*
    }
    handle @not_tec {
        rewrite /user/login /user/oauth2/authelia
        reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
            @404 status 404
            handle_response @404 {
                header +Set-Cookie "caddy_tec_redirect=true; Max-Age=5"
                redir * /tec{uri}
            }
        }
    }
    @tec_redirect {
        path /tec/*
        header Cookie *caddy_tec_redirect=true*
    }
    handle @tec_redirect {
        reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT} {
            @404 status 404
            handle_response @404 {
                header +Set-Cookie "caddy_tec_redirect=true; Max-Age=0"
                handle_path /tec/* {
                    redir * {uri}
                }
            }
        }
    }
    handle {
        rewrite /user/login /user/oauth2/authelia
        reverse_proxy localhost:${toString config.services.forgejo.settings.server.HTTP_PORT}
    }
    '';

  services.caddy.virtualHosts."${blog-domain}".extraConfig =
    ''
    redir /tmio /tmio/
    handle_path /tmio/* {
        file_server {
            fs git ${config.services.forgejo.stateDir}/repositories/tec/this-month-in-org.git html
        }
    }
    handle {
        respond 404
    }
    '';
}
