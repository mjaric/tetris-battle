#!/usr/bin/env bash
# Bootstrap script to clone all dependencies from git.
# Required because mix deps.get may fail on large repos through certain proxies.
# Run this script instead of `mix deps.get`.

set -e

cd "$(dirname "$0")"

mkdir -p deps

declare -A REPOS
REPOS[phoenix]="https://github.com/phoenixframework/phoenix.git v1.7.20"
REPOS[jason]="https://github.com/michalmuskala/jason.git v1.4.4"
REPOS[plug_cowboy]="https://github.com/elixir-plug/plug_cowboy.git v2.7.3"
REPOS[corsica]="https://github.com/whatyouhide/corsica.git v2.1.3"
REPOS[telemetry]="https://github.com/beam-telemetry/telemetry.git v1.3.0"
REPOS[phoenix_pubsub]="https://github.com/phoenixframework/phoenix_pubsub.git v2.1.3"
REPOS[phoenix_template]="https://github.com/phoenixframework/phoenix_template.git v1.0.4"
REPOS[plug]="https://github.com/elixir-plug/plug v1.16.1"
REPOS[plug_crypto]="https://github.com/elixir-plug/plug_crypto.git v2.1.0"
REPOS[cowboy]="https://github.com/ninenines/cowboy.git 2.12.0"
REPOS[cowlib]="https://github.com/ninenines/cowlib.git 2.13.0"
REPOS[ranch]="https://github.com/ninenines/ranch.git 1.8.1"
REPOS[cowboy_telemetry]="https://github.com/beam-telemetry/cowboy_telemetry.git v0.4.0"
REPOS[telemetry_poller]="https://github.com/beam-telemetry/telemetry_poller.git v1.1.0"
REPOS[telemetry_metrics]="https://github.com/beam-telemetry/telemetry_metrics.git v1.1.0"
REPOS[websock_adapter]="https://github.com/phoenixframework/websock_adapter 0.5.8"
REPOS[websock]="https://github.com/phoenixframework/websock.git 0.5.3"
REPOS[mime]="https://github.com/elixir-plug/mime v2.0.6"
REPOS[castore]="https://github.com/elixir-mint/castore.git v1.0.17"

for dep in "${!REPOS[@]}"; do
  read url tag <<< "${REPOS[$dep]}"
  if [ -d "deps/$dep/.git" ]; then
    echo "SKIP: $dep (already cloned)"
    continue
  fi
  echo "Cloning $dep @ $tag..."
  rm -rf "deps/$dep"
  if git clone --depth 1 --branch "$tag" "$url" "deps/$dep" 2>/dev/null; then
    # Ensure origin URL has .git suffix for Mix compatibility
    cd "deps/$dep"
    origin=$(git remote get-url origin 2>/dev/null || echo "")
    if [ -n "$origin" ]; then
      git remote set-url origin "${url%.git}.git" 2>/dev/null || true
    else
      git remote add origin "${url%.git}.git" 2>/dev/null || true
    fi
    cd ../..
    echo "  OK: $dep"
  else
    echo "  FAILED: $dep (retrying without .git suffix)"
    url_no_git="${url%.git}"
    git clone --depth 1 --branch "$tag" "$url_no_git" "deps/$dep" 2>/dev/null && echo "  OK: $dep" || echo "  FAILED: $dep"
  fi
done

# Remove castore's certdata mix task (incompatible with OTP 27 in some environments)
if [ -f deps/castore/lib/mix/tasks/certdata.ex ]; then
  rm deps/castore/lib/mix/tasks/certdata.ex
fi

echo ""
echo "Dependencies cloned. Run 'mix compile' to build."
