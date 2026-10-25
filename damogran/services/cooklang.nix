{ config, domain, pkgs, ... }:
let
  hostName = "recipes.${domain}";
in
{
  imports = [ ../../modules/cooklang.nix ];

  services.cooklang = {
    enable = true;
    # Nixpkgs 0.30.0 builds CSS but omits the editor JavaScript bundle.
    package = pkgs.cook-cli.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace templates/recipe.html \
          --replace-fail '<div>' '<div class="recipe-page">'
        cat >> static/css/custom-styles.css <<'CSS'
        /* Keep recipe content within the viewport, including standalone PWAs. */
        .recipe-page {
            overflow-wrap: anywhere;
        }
        .recipe-page .grid > *,
        .recipe-page .flex > * {
            min-width: 0;
        }
        .recipe-page .ingredient-badge,
        .recipe-page .cookware-badge,
        .recipe-page .timer-badge,
        .recipe-page .metadata-pill {
            white-space: normal;
            max-width: 100%;
        }
        .recipe-page .breadcrumb ol {
            flex-wrap: wrap;
            row-gap: 0.25rem;
        }
        CSS
      '';
      preBuild = (old.preBuild or "") + ''
        npm run build-js
      '';
    });
  };

  # CookCLI 0.30 permits arbitrary CORS origins; reject foreign browser origins
  # at the proxy, while allowing same-origin requests and non-browser clients.
  services.nginx.commonHttpConfig = ''
    map $http_origin $cooklang_origin_allowed {
      default 0;
      "" 1;
      "https://${hostName}" 1;
    }
  '';
  services.nginx.virtualHosts.${hostName}.extraConfig = ''
    if ($cooklang_origin_allowed = 0) { return 403; }
  '';

  # Terminate TLS locally so the Tailscale ACL sees the real client address.
  ingress.cooklang = {
    subdomain = "recipes";
    port = config.services.cooklang.port;
    tailscaleOnly = true;
  };

  security.acme.certs.${hostName} = {
    webroot = null;
    dnsProvider = "cloudflare";
    environmentFile = config.sops.secrets."cloudflare/dns-api-token-env".path;
    dnsPropagationCheck = true;
    dnsResolver = "1.1.1.1:53";
  };
  sops.secrets."cloudflare/dns-api-token-env" = { };

  services.headscale.settings.dns.extra_records = [
    {
      name = hostName;
      type = "A";
      value = "100.64.0.3";
    }
  ];
}
