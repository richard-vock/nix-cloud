{ config, domain, pkgs, ... }:
let
  hostName = "recipes.${domain}";
in
{
  imports = [ ../../modules/cooklang.nix ];

  services.cooklang = {
    enable = true;
    # Use the official Nixpkgs 0.38.1 hashes without updating the flake inputs.
    package = pkgs.cook-cli.overrideAttrs (finalAttrs: old: {
      version = "0.38.1";
      src = pkgs.fetchFromGitHub {
        owner = "cooklang";
        repo = "cookcli";
        rev = "v${finalAttrs.version}";
        hash = "sha256-XvEUpPrkgWxtBoInx6jM0gHF3igZcyf5ykR9Z3wQScc=";
      };
      cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
        inherit (finalAttrs) pname version src;
        hash = "sha256-gbJo6qzj2c3tzZuEjP8/XxJQjbZrYbjZAWIkqfpwhiM=";
      };
      npmDeps = pkgs.fetchNpmDeps {
        inherit (finalAttrs) src;
        hash = "sha256-zAtFsSpJFdthb0E8FLVRGWzGcReDsZxZF+NvHZ+wcY4=";
      };
      # These were not feature-gated in 0.30; keep self-update disabled.
      cargoBuildFeatures = [ "server" "import" "lsp" ];
      cargoCheckFeatures = finalAttrs.cargoBuildFeatures;
      postPatch = (old.postPatch or "") + ''
        substituteInPlace templates/recipe.html \
          --replace-fail '<div>' '<div class="recipe-page">'
        cat >> static/css/input.css <<'CSS'
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

  # CookCLI 0.38 also checks Host and Origin behind reverse proxies.
  systemd.services.cooklang.environment.COOK_CORS_ORIGIN = "https://${hostName}";

  # Reject foreign browser origins at the proxy, while allowing same-origin
  # requests and non-browser clients.
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
