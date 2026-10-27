#!/bin/sh
set -e
bundle=${1:-/me/Apps/ViewerPR1.app}
sources=`dirname "$0"`
test -d "$bundle/Resources"
cc -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/ViewerCompat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/ViewerCompat.dylib.new" "$sources/compat.m" "$sources/../common/appkit-compat.m" \
    -framework AppKit -framework Foundation
cc -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/ToolCompat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/ToolCompat.dylib.new" "$sources/tool-compat.m" -framework Foundation
cc -o "$bundle/OpenItem.new" "$sources/../common/viewer-open-item.m" -framework AppKit -framework Foundation
mv "$bundle/ViewerCompat.dylib.new" "$bundle/ViewerCompat.dylib"
mv "$bundle/ToolCompat.dylib.new" "$bundle/ToolCompat.dylib"
mv "$bundle/OpenItem.new" "$bundle/OpenItem"
chmod 755 "$bundle/ViewerPR1" "$bundle/OpenItem"
