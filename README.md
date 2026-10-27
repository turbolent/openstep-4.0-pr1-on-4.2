# OPENSTEP PR1 and Rhapsody DR2 apps on OPENSTEP 4.2

This project ports the Dock, Viewer, and MailViewer from OPENSTEP 4.0 Pre-release 1 (PR1) to OPENSTEP 4.2 for Intel.
It also ports MailViewer and Stickies from Rhapsody Developer Release 2 (DR2).
The builders patch the original executables and add compatibility helpers compiled from the included source.
The Dock comes from PR1's `Workspace.app`.

The builders create patched app bundles and installation archives from stock apps and frameworks.

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

Prepare the DR2 apps from an extracted DR2 system tree:

```sh
dr2="/path/to/DR2"

python3 -B tools/build.py mailviewer-dr2 \
  --source "$dr2/System/Applications/MailViewer.app" \
  --frameworks "$dr2/System/Library" \
  --output "$out/MailViewerDR2.app" \
  --install-path /LocalApps/MailViewerDR2.app

python3 -B tools/build.py stickies-dr2 \
  --source "$dr2/System/Demos/Stickies.app" \
  --output "$out/StickiesDR2.app" \
  --install-path /LocalApps/StickiesDR2.app
```

Install each archive and compile its compatibility source on OPENSTEP 4.2
as described for [MailViewer](tools/MailViewerDR2/README.md#usage)
and [Stickies](tools/StickiesDR2/README.md#usage).
