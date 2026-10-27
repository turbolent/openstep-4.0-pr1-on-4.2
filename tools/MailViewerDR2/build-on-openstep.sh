#!/bin/sh
set -e
sources=`dirname "$0"`
bundle=`cd "$sources/.." && pwd`
expected=`cat "$bundle/Compatibility/install-path"`
if [ "$bundle" != "$expected" ]; then
    echo "Install this app at $expected before compiling." >&2
    exit 1
fi
cc -fno-common -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/DR2Compat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/DR2Compat.dylib.new" \
    "$bundle/Compatibility/compat.m" \
    "$bundle/Compatibility/undo.m" "$bundle/Compatibility/common/dr2-appkit.m" \
    "$bundle/Compatibility/common/dr2-paths.m" \
    "$bundle/Compatibility/common/dr2-abi.m" "$bundle/Compatibility/common/dr2-popup.m" -framework AppKit -framework Foundation
mv "$bundle/DR2Compat.dylib.new" "$bundle/DR2Compat.dylib"
chmod 755 "$bundle/MailViewerDR2"
echo "Built $bundle"
