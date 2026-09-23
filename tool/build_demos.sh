#!/usr/bin/env bash
# Builds the documentation site's live demos: both example apps for the web,
# running against their in-memory backends (no server), into
# website/static/demo/<app>/, where Docusaurus copies them into the site.
#
#   tool/build_demos.sh              # both apps
#   tool/build_demos.sh showcase     # one of them
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

base_url="${SITE_BASE_URL:-$(sed -En "s/^[[:space:]]*baseUrl:[[:space:]]*['\"]([^'\"]*)['\"].*/\1/p" "$site/docusaurus.config.ts" | head -n 1)}"
if [[ -z "$base_url" || "$base_url" != /*/ ]]; then
  echo "build_demos: could not read baseUrl from website/docusaurus.config.ts (got '$base_url')" >&2
  exit 1
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
