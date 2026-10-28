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
pswrap -o "$sources/contexts.raw.c" -h "$sources/contexts.h" "$sources/contexts.psw"
sed 's,dpsclient/dpsfriends.h,AppKit/dpsfriends.h,' \
    "$sources/contexts.raw.c" > "$sources/contexts.c"
rm "$sources/contexts.raw.c"
cc -fno-common -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/DR2Compat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/DR2Compat.dylib.new" "$sources/compat.m" "$sources/viewer.m" "$sources/contexts.c" \
    "$sources/common/dr2-abi.m" "$sources/common/dr2-appkit.m" \
    "$sources/common/dr2-paths.m" -framework AppKit -framework Foundation
mv "$bundle/DR2Compat.dylib.new" "$bundle/DR2Compat.dylib"
chmod 755 "$bundle/WorkspaceDR2"
echo "Built $bundle"
