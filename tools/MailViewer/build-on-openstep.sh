#!/bin/sh
set -e
bundle=${1:-/me/Apps/MailViewerPR1.app}
sources=`dirname "$0"`
test -d "$bundle/Resources"
cc -dynamiclib -undefined suppress \
    -Wl,-install_name,"$bundle/MailViewerCompat.dylib",-compatibility_version,1.0,-current_version,1.0 \
    -o "$bundle/MailViewerCompat.dylib.new" "$sources/compat.m" "$sources/../common/appkit-compat.m" \
    -framework AppKit -framework Foundation
mv "$bundle/MailViewerCompat.dylib.new" "$bundle/MailViewerCompat.dylib"
chmod 755 "$bundle/MailViewerPR1"
