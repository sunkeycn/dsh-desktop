#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
plugin_dir=${DSH_PET_DIR:-$HOME/.dsh/profiles/web/node_modules/dsh-pet}

if [[ ! -f "$plugin_dir/package.json" ]]; then
  print -u2 "dsh-pet is not installed at: $plugin_dir"
  exit 1
fi

if /usr/bin/grep -q 'const isAppleWebKit' "$plugin_dir/lib/client.js" \
    && /usr/bin/grep -q '".mov": "video/quicktime"' "$plugin_dir/lib/index.js"; then
  print "dsh-pet code patch is already installed"
else
  /usr/bin/patch --batch --forward -d "$plugin_dir" -p1 < "$script_dir/dsh-pet-hevc-alpha.patch"
fi

DSH_PET_DIR="$plugin_dir" "$script_dir/convert-hevc-alpha.sh"
print "dsh-pet HEVC-alpha patch installed; restart DSH to reload the host MIME map"
