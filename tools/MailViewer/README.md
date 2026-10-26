# MailViewer PR1 on OPENSTEP 4.2

This builder ports the MailViewer mail application from OPENSTEP 4.0 Pre-release 1 to OPENSTEP 4.2 for Intel.
It patches the original executable and adds a compatibility helper compiled from the included source.
Building requires the stock PR1 `MailViewer.app`, `Message.framework`, and `NeXTApps.framework` bundles.

## Usage

Run this command from the repository root with Python 3.10 or later.
Set `pr1` to the directory containing your extracted PR1 files, including each bundle's `Resources` directory.
Set `out` to an empty output directory.
Keep both directories outside this repository.

```sh
pr1="/path/to/PR1"
out="/path/to/patched-apps"

python3 -B tools/build.py mailviewer \
  --source "$pr1/NextApps/MailViewer.app" \
  --message "$pr1/NextLibrary/PrivateFrameworks/Message.framework" \
  --nextapps "$pr1/NextLibrary/PrivateFrameworks/NeXTApps.framework" \
  --output "$out/MailViewerPR1.app"
```

The command creates `MailViewerPR1.app` and `MailViewerPR1-OPENSTEP42.tar.gz` in `$out`.
The default OPENSTEP path is `/me/Apps/MailViewerPR1.app`.
Use `--install-path` to embed a different OPENSTEP app path when building.
