# MailViewer DR2

This builder ports Rhapsody DR2's Intel MailViewer to OPENSTEP 4.2.
It adapts the executable, bundled frameworks, menus, and controls,
and adds text Undo and Redo in Compose.
The port uses a separate application identity and defaults to `~/MailboxesDR2` for mailboxes.

## Usage

Run from the repository root with Python 3.10 or later.
Set `dr2` to an extracted DR2 system tree containing `System/Applications/MailViewer.app`
and `System/Library` with the MailViewer, Message, AppSupport, and HTML frameworks.
Keep stock files and generated apps outside the repository.

```sh
dr2="/path/to/DR2"
out="/path/to/patched-apps"
app="/LocalApps/MailViewerDR2.app"

python3 -B tools/build.py mailviewer-dr2 \
  --source "$dr2/System/Applications/MailViewer.app" \
  --frameworks "$dr2/System/Library" \
  --output "$out/MailViewerDR2.app" \
  --install-path "$app"
```

Copy `MailViewerDR2-OPENSTEP42.tar.gz` to OPENSTEP 4.2 with its Developer tools installed.
Extract it at the exact `--install-path`, then compile the included compatibility source:

```sh
app="/LocalApps/MailViewerDR2.app"
mkdir "$app"
cd "$app"
gzip -dc /path/to/MailViewerDR2-OPENSTEP42.tar.gz | tar xf -
sh Compatibility/build-on-openstep.sh
open "$app"
```

Choose a writable parent directory that already exists.
The app is ready to launch after compilation succeeds.
