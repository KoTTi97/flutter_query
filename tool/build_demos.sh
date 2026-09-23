#!/usr/bin/env bash
# Builds the documentation site's live demos: both example apps for the web,
# running against their in-memory backends (no server), into
# website/static/demo/<app>/, where Docusaurus copies them into the site.
#
#   tool/build_demos.sh              # both apps
#   tool/build_demos.sh showcase     # one of them
#   tool/build_demos.sh --print-base-url
#
# The output is build output: it is gitignored and never committed (plan D5).
# CI runs this before `npm run build` in the `website` job; locally,
# `npm run demos` in website/ runs it.
#
# The base href is derived from the site's own `baseUrl`
# (website/docusaurus.config.ts), so renaming the repository — and with it the
# Pages path — is one edit there. SITE_BASE_URL overrides it.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site="$root/website"

# Reads the site's baseUrl from its config without running it (running it
# needs the site's node_modules). The spellings understood, first match wins:
#
#   baseUrl: '/x/',                      a literal in the config object
#   const baseUrl = '/x/'                a top-level constant
#   const baseUrl = `/${repository}/`    a template over top-level string
#                                        constants (const repository = 'x')
#
# Anything else is an error, not a guess.
config_base_url() {
  local config="$site/docusaurus.config.ts"
  local quote="['\"\`]"
  local body="[^'\"\`]*"
  local value name constant
  value="$(sed -En "s/^[[:space:]]*baseUrl:[[:space:]]*${quote}(${body})${quote}.*/\1/p" "$config" | head -n 1)"
  if [[ -z "$value" ]]; then
    value="$(sed -En "s/^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+baseUrl[[:space:]]*=[[:space:]]*${quote}(${body})${quote}.*/\2/p" "$config" | head -n 1)"
  fi
  # Each ${name} in a template resolves to a top-level `const name = '...'`.
  local pattern='\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
  while [[ "$value" =~ $pattern ]]; do
    name="${BASH_REMATCH[1]}"
    constant="$(sed -En "s/^[[:space:]]*(export[[:space:]]+)?const[[:space:]]+${name}[[:space:]]*=[[:space:]]*['\"]([^'\"]*)['\"].*/\2/p" "$config" | head -n 1)"
    if [[ -z "$constant" ]]; then
      echo "build_demos: baseUrl uses \${$name}, which is not a string constant in website/docusaurus.config.ts" >&2
      return 1
    fi
    value="${value//"\${$name}"/$constant}"
  done
  printf '%s\n' "$value"
}

if [[ -n "${SITE_BASE_URL:-}" ]]; then
  base_url="$SITE_BASE_URL"
else
  base_url="$(config_base_url)"
fi
if [[ -z "$base_url" || "$base_url" != /*/ ]]; then
  echo "build_demos: could not read baseUrl from website/docusaurus.config.ts (got '$base_url'); set SITE_BASE_URL" >&2
  exit 1
fi

# `--print-base-url` prints the base URL the builds would use, and stops.
if [[ "${1:-}" == "--print-base-url" ]]; then
  echo "$base_url"
  exit 0
fi

apps=("$@")
if [[ ${#apps[@]} -eq 0 ]]; then
  apps=(showcase task_manager)
fi

# The builds pass --no-pub so they never rewrite the root pubspec.lock; the
# workspace has to be resolved once beforehand.
if [[ ! -f "$root/.dart_tool/package_config.json" ]]; then
  (cd "$root" && flutter pub get)
fi

for app in "${apps[@]}"; do
  case "$app" in
    showcase | task_manager) ;;
    *)
      echo "build_demos: unknown app '$app' (showcase, task_manager)" >&2
      exit 1
      ;;
  esac
  out="$site/static/demo/$app"
  href="${base_url}demo/$app/"
  echo "build_demos: $app -> ${out#"$root"/} (base href $href)"
  rm -rf "$out"
  # --no-web-resources-cdn: CanvasKit from this build, not from gstatic — no
  #   third-party request, the engine pinned to the build.
  # --pwa-strategy=none: no service worker under the docs origin serving a
  #   stale demo after a deploy.
  (cd "$root/examples/$app" && flutter build web --release --no-pub \
    --no-web-resources-cdn --pwa-strategy=none \
    --dart-define=QK_BACKEND=inmemory \
    --base-href "$href" \
    --output "$out")
  # What a JavaScript build never downloads: the engine's debug symbols and
  # the skwasm renderer (a --wasm build's). CanvasKit stays, in both its
  # variants — Chromium browsers take canvaskit/chromium/, the rest canvaskit/.
  find "$out/canvaskit" -name '*.symbols' -delete
  find "$out/canvaskit" -name 'skwasm*' -delete
  rm -f "$out/.last_build_id"
  echo "build_demos: $app is $(du -sh "$out" | cut -f1) on disk"
done
