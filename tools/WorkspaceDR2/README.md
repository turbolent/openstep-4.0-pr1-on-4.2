# Workspace DR2

This builder ports Rhapsody DR2's Applications menu to OPENSTEP 4.2 for Intel.
The original menu runs in `WorkspaceDR2.app`, with app switching, Hide, Hide Others,
Show All, and a process panel adapted to OPENSTEP's application services.
The native Workspace, WindowServer, and pasteboard server continue to manage the desktop.
The compatibility helpers are compiled from source on OPENSTEP 4.2.

## Usage

Run from the repository root with Python 3.10 or later.
Set `dr2` to an extracted DR2 system tree containing the stock `Workspace.app`,
including its `Resources` directory.
Keep stock files and generated apps outside the repository.

```sh
dr2="/path/to/DR2"
out="/path/to/patched-apps"
app="/LocalApps/WorkspaceDR2.app"

python3 -B tools/build.py workspace-dr2 \
  --source "$dr2/System/Library/CoreServices/Workspace.app" \
  --output "$out/WorkspaceDR2.app" \
  --install-path "$app"
```

Copy `WorkspaceDR2-OPENSTEP42.tar.gz` to OPENSTEP 4.2 with its Developer tools installed.
Extract it at the exact `--install-path`, then compile the compatibility source:

```sh
app="/LocalApps/WorkspaceDR2.app"
mkdir "$app"
cd "$app"

gzip -dc /path/to/WorkspaceDR2-OPENSTEP42.tar.gz | gnutar xf -
sh Compatibility/build-on-openstep.sh
open "$app"
```

Choose a writable parent directory that already exists.
The app is ready to launch after compilation succeeds.
