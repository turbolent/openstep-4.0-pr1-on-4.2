# OPENSTEP PR1, Rhapsody DR2, and Mac OS X apps on OPENSTEP 4.2

This project ports the Dock, Viewer, and MailViewer from OPENSTEP 4.0 Pre-release 1 (PR1) to OPENSTEP 4.2 for Intel.
It also ports Viewer, MailViewer, and Stickies from Rhapsody Developer Release 2 (DR2).
It also ports Terminal from Intel Mac OS X Tiger and Mac OS X Snow Leopard.
DR2 Workspace's Applications menu runs as a separate app beside the native Workspace.
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

python3 -B tools/build.py workspace-dr2 \
  --source "$dr2/System/Library/CoreServices/Workspace.app" \
  --output "$out/WorkspaceDR2.app" \
  --install-path /LocalApps/WorkspaceDR2.app

python3 -B tools/build.py viewer-dr2 \
  --source "$dr2/System/Library/CoreServices/Viewer.app" \
  --appsupport "$dr2/System/Library/PrivateFrameworks/AppSupport.framework" \
  --output "$out/ViewerDR2.app" \
  --install-path /LocalApps/ViewerDR2.app

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
as described for [Workspace](tools/WorkspaceDR2/README.md#usage),
[Viewer](tools/ViewerDR2/README.md#usage),
[MailViewer](tools/MailViewerDR2/README.md#usage),
and [Stickies](tools/StickiesDR2/README.md#usage).

The [DR2 framework runtime](tools/common/dr2-runtime/README.md)
packages Stickies, Viewer, MailViewer, Project Builder, and Preview with DR2's original AppKit, Foundation, fonts, and private services.
The generated app bundles open directly from Workspace.

Prepare Terminal from Intel Tiger 10.4.1 build 8B1025. The builder verifies this
specific executable; the retail Tiger DVD's PowerPC-only Terminal is unsupported.
Install the Python dependencies before building:

```sh
tiger="/path/to/Tiger-10.4.1-8B1025"

python3 -m pip install -r tools/TerminalTiger/requirements.txt
python3 -B tools/build.py terminal-tiger \
  --source "$tiger/Applications/Utilities/Terminal.app" \
  --output "$out/TerminalTiger" \
  --runtime-directory /LocalApps/TerminalTiger
```

This creates `TerminalTiger.app`, compatibility source, and
`TerminalTiger-source-bundle.tar.gz` inside `$out/TerminalTiger`.
Extract the archive into `/LocalApps/TerminalTiger` on OPENSTEP and run
`sh build-on-openstep.sh` there with the native compiler, then open
`TerminalTiger.app` in Workspace. The runtime directory is embedded in the app;
rebuild with a different `--runtime-directory` to relocate it.
See [Tiger Terminal](tools/TerminalTiger/README.md) for build and installation instructions.

Prepare Terminal from Mac OS X Snow Leopard 10.6.8:

```sh
snow="/path/to/Snow-Leopard-10.6.8"

python3 -m pip install -r tools/TerminalSnowLeopard/requirements.txt
python3 -B tools/build.py terminal-snow-leopard \
  --source "$snow/Applications/Utilities/Terminal.app" \
  --output "$out/TerminalSnowLeopard" \
  --runtime-directory /LocalApps/TerminalSnowLeopard
```

Extract `TerminalSnowLeopard-source-bundle.tar.gz` into the runtime directory on
OPENSTEP, run `sh build-on-openstep.sh`, then open `TerminalSnowLeopard.app`.
Each shell uses a separate window. See [Snow Leopard Terminal](tools/TerminalSnowLeopard/README.md)
for prerequisites and installation instructions.
