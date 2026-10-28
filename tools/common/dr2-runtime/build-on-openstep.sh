#!/bin/sh
set -e
directory=`dirname "$0"`
runtime=`cd "$directory" && pwd`
expected=@INSTALL_PATH@
if [ "$runtime" != "$expected" ]; then
    echo "Install the runtime at $expected before compiling." >&2
    exit 1
fi
sources="$runtime/Compatibility"
cc -fno-common -dynamiclib -undefined suppress -I"$sources/dr2-runtime" \
    -Wl,-install_name,"$runtime/ABI.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$runtime/ABI.dylib.new" \
    "$sources/dr2-runtime/abi.m" "$sources/dr2-runtime/bsd.m" \
    "$sources/dr2-runtime/appkit.m" "$sources/dr2-runtime/application.m"
mv "$runtime/ABI.dylib.new" "$runtime/ABI.dylib"
if [ -d "$runtime/Apps/ViewerDR2Runtime.app" ]; then
    cc -fno-common -dynamiclib -undefined suppress -I"$sources/dr2-runtime" \
        -Wl,-install_name,"$runtime/ViewerRuntime.dylib",-compatibility_version,1.0,-current_version,1.0 \
        -o "$runtime/ViewerRuntime.dylib.new" "$sources/dr2-runtime/viewer.m"
    mv "$runtime/ViewerRuntime.dylib.new" "$runtime/ViewerRuntime.dylib"
fi
if [ -d "$runtime/Apps/ProjectBuilderDR2Runtime.app" ]; then
    cc -fno-common -dynamiclib -undefined suppress -I"$sources/dr2-runtime" \
        -Wl,-install_name,"$runtime/ProjectBuilderRuntime.dylib",-compatibility_version,1.0,-current_version,1.0 \
        -o "$runtime/ProjectBuilderRuntime.dylib.new" "$sources/dr2-runtime/projectbuilder.m"
    mv "$runtime/ProjectBuilderRuntime.dylib.new" "$runtime/ProjectBuilderRuntime.dylib"
    for resource in pb_makefiles project; do
        if [ ! -d "$runtime/Developer/Makefiles/$resource" ]; then
            ln -s "/NextDeveloper/Makefiles/$resource" "$runtime/Developer/Makefiles/$resource"
        fi
    done
fi
chmod 755 "$runtime/pbs-dr2" "$runtime/fcache"
echo "Built $runtime"
