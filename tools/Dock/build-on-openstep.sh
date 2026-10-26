#!/bin/sh
set -e
# Quit Dock PR1 before rebuilding its loaded library.
bundle=${1:-/me/Apps/DockPR1.app}
sources=`dirname "$0"`
test -d "$bundle/Resources"
cc -dynamiclib -undefined suppress \
  -Wl,-install_name,"$bundle/PR1Compat.dylib",-compatibility_version,1.0,-current_version,1.0 \
  -o "$bundle/PR1Compat.dylib.new" "$sources/compat.m" \
  -framework AppKit -framework Foundation
cc -o "$bundle/OpenItem.new" "$sources/open-item.m" \
  -framework AppKit -framework Foundation
mv "$bundle/PR1Compat.dylib.new" "$bundle/PR1Compat.dylib"
mv "$bundle/OpenItem.new" "$bundle/OpenItem"
chmod 755 "$bundle/DockPR1" "$bundle/OpenItem"
echo "Built Dock PR1 helpers in $bundle"
