# Viewer DR2

This builder ports Rhapsody DR2's Intel Viewer to OPENSTEP 4.2.
It adapts the original file browser, inspectors, and background tools
to run beside the native Workspace as `ViewerDR2.app`.
The compatibility helpers are compiled from source on OPENSTEP 4.2.

## Usage

Run from the repository root with Python 3.10 or later.
Set `dr2` to an extracted DR2 system tree containing Viewer and AppSupport,
including their `Resources` directories.
Keep stock files and generated apps outside the repository.

```sh
dr2="/path/to/DR2"
out="/path/to/patched-apps"
app="/LocalApps/ViewerDR2.app"

python3 -B tools/build.py viewer-dr2 \
  --source "$dr2/System/Library/CoreServices/Viewer.app" \
  --appsupport "$dr2/System/Library/PrivateFrameworks/AppSupport.framework" \
  --output "$out/ViewerDR2.app" \
  --install-path "$app"
```

Copy `ViewerDR2-OPENSTEP42.tar.gz` to OPENSTEP 4.2 with its Developer tools installed.
Extract it at the exact `--install-path`, then compile the compatibility source:

```sh
app="/LocalApps/ViewerDR2.app"
mkdir "$app"
cd "$app"

gzip -dc /path/to/ViewerDR2-OPENSTEP42.tar.gz | gnutar xf -
sh Compatibility/build-on-openstep.sh
open "$app"
```

Choose a writable parent directory that already exists.
The app is ready to launch after compilation succeeds.
