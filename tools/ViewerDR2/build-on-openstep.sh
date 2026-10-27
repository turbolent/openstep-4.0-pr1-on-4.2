#!/bin/sh
set -e
sources=`dirname "$0"`
bundle=`cd "$sources/.." && pwd`
expected=`cat "$bundle/Compatibility/install-path"`
if [ "$bundle" != "$expected" ]; then
    echo "Install this app at $expected before compiling." >&2
    exit 1
fi
sources="$bundle/Compatibility"
cc -fno-common -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/DR2Compat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/DR2Compat.dylib.new" \
    "$sources/compat.m" "$sources/attributes.m" "$sources/common/dr2-abi.m" \
    "$sources/common/dr2-appkit.m" "$sources/common/dr2-paths.m" \
    "$sources/common/dr2-popup.m" -framework AppKit -framework Foundation
cc -DVIEWER_DR2 -fno-common -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/ToolCompat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/ToolCompat.dylib.new" "$sources/common/viewer-tool.m" \
    "$sources/attributes.m" "$sources/common/dr2-abi.m" -framework AppKit -framework Foundation
cc -fno-common -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/RuntimeCompat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/RuntimeCompat.dylib.new" "$sources/common/dr2-abi.m" \
    -framework AppKit -framework Foundation
cc -o "$bundle/OpenItem.new" "$sources/common/viewer-open-item.m" \
    -framework AppKit -framework Foundation
cc -o "$sources/cache.new" "$sources/cache.m" -framework Foundation
"$sources/cache.new" "$bundle/Resources/default.apps5_1.table"
rm "$sources/cache.new"
for name in DR2Compat.dylib ToolCompat.dylib RuntimeCompat.dylib OpenItem; do
    mv "$bundle/$name.new" "$bundle/$name"
done
chmod 755 "$bundle/ViewerDR2" "$bundle/OpenItem" "$bundle/search"
echo "Built $bundle"
