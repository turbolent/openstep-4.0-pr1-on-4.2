# OPENSTEP 4.0 PR1 apps on OPENSTEP 4.2

This project ports the Dock, Viewer, and MailViewer from OPENSTEP 4.0 Pre-release 1 (PR1) to OPENSTEP 4.2 for Intel.
The builders patch the original executables and add compatibility helpers compiled from the included source.
The Dock comes from PR1's `Workspace.app`.

The builders create patched app bundles and installation archives from stock PR1 apps and frameworks.

## Usage

Run these commands from the repository root with Python 3.10 or later.
Set `pr1` to the directory containing your extracted PR1 files, including each bundle's `Resources` directory.
Set `out` to an empty output directory.
Keep both directories outside this repository.

```sh
pr1="/path/to/PR1"
out="/path/to/patched-apps"

python3 -B tools/build.py dock \
  --source "$pr1/NextApps/Workspace.app" \
  --output "$out/DockPR1.app"

python3 -B tools/build.py viewer \
  --source "$pr1/NextApps/Viewer.app" \
  --nextapps "$pr1/NextLibrary/PrivateFrameworks/NeXTApps.framework" \
  --output "$out/ViewerPR1.app"

python3 -B tools/build.py mailviewer \
  --source "$pr1/NextApps/MailViewer.app" \
  --message "$pr1/NextLibrary/PrivateFrameworks/Message.framework" \
  --nextapps "$pr1/NextLibrary/PrivateFrameworks/NeXTApps.framework" \
  --output "$out/MailViewerPR1.app"
```

These commands create `DockPR1.app`, `ViewerPR1.app`, and `MailViewerPR1.app` in `$out`, with an installation archive beside each app.

The default OPENSTEP paths are `/me/Apps/DockPR1.app`, `/me/Apps/ViewerPR1.app`, and `/me/Apps/MailViewerPR1.app`.
Use `--install-path` to embed a different OPENSTEP app path when building.
