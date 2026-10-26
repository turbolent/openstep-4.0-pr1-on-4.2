# Dock PR1 on OPENSTEP 4.2

This builder extracts the tabbed Dock from OPENSTEP 4.0 Pre-release 1's `Workspace.app` and ports it to OPENSTEP 4.2 for Intel.
It patches the original executable and adds compatibility helpers compiled from the included source.
Building requires the stock PR1 `Workspace.app` bundle.

## Usage

Run this command from the repository root with Python 3.10 or later.
Set `pr1` to the directory containing your extracted PR1 files, including each bundle's `Resources` directory.
Set `out` to an empty output directory.
Keep both directories outside this repository.

```sh
pr1="/path/to/PR1"
out="/path/to/patched-apps"

python3 -B tools/build.py dock \
  --source "$pr1/NextApps/Workspace.app" \
  --output "$out/DockPR1.app"
```

The command creates `DockPR1.app` and `DockPR1-OPENSTEP42.tar.gz` in `$out`.
The default OPENSTEP path is `/me/Apps/DockPR1.app`.
Use `--install-path` to embed a different OPENSTEP app path when building.
