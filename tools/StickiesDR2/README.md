# Stickies DR2

This builder ports Rhapsody DR2's Intel Stickies to OPENSTEP 4.2.
It adapts the executable, menus, and controls while retaining the app's note editing and undo system.
The port stores notes in `~/Library/.StickiesDR2Notes` under a separate application identity.

## Usage

Run from the repository root with Python 3.10 or later.
Set `dr2` to an extracted DR2 system tree containing `System/Demos/Stickies.app`,
including its `Resources` directory and `.StickiesDatabase` sample notes.
Keep stock files and generated apps outside the repository.

```sh
dr2="/path/to/DR2"
out="/path/to/patched-apps"
app="/LocalApps/StickiesDR2.app"

python3 -B tools/build.py stickies-dr2 \
  --source "$dr2/System/Demos/Stickies.app" \
  --output "$out/StickiesDR2.app" \
  --install-path "$app"
```

Copy `StickiesDR2-OPENSTEP42.tar.gz` to OPENSTEP 4.2 with its Developer tools installed.
Extract it at the exact `--install-path`, then compile the included compatibility source:

```sh
app="/LocalApps/StickiesDR2.app"
mkdir "$app"
cd "$app"

gzip -dc /path/to/StickiesDR2-OPENSTEP42.tar.gz | tar xf -
sh Compatibility/build-on-openstep.sh
open "$app"
```

Choose a writable parent directory that already exists.
The app is ready to launch after compilation succeeds.
