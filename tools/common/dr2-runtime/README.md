# DR2 framework runtime

This builder runs stock Rhapsody DR2 apps with DR2's AppKit,
Foundation, fonts, and private support services on OPENSTEP 4.2 for Intel.
It patches user-supplied DR2 files and adds a compatibility library compiled from source.
It builds separate Stickies, Viewer, MailViewer, and Project Builder variants named `*DR2Runtime.app`.
The existing `stickies-dr2`, `viewer-dr2`, and `mailviewer-dr2` builders continue to use OPENSTEP's frameworks.

## Usage

Run from the repository root with Python 3.10 or later.
Set `dr2` to an extracted DR2 system tree containing its frameworks, fonts, and tools.
Keep stock files and generated output outside the repository.

```sh
dr2="/path/to/DR2"
out="/path/to/patched-apps"
runtime="/me/DR2Runtime"

python3 -B tools/build.py runtime-dr2 \
  --source "$dr2" \
  --app "$dr2/System/Demos/Stickies.app" \
  --app "$dr2/System/Library/CoreServices/Viewer.app" \
  --app "$dr2/System/Applications/MailViewer.app" \
  --app "$dr2/System/Developer/Applications/ProjectBuilder.app" \
  --output "$out/DR2Runtime" \
  --install-path "$runtime"
```

Copy `DR2Runtime-OPENSTEP42.tar.gz` to OPENSTEP 4.2 with its Developer tools installed.
Choose a writable parent directory and extract at the exact `--install-path`.
Run the build commands on OPENSTEP:

```sh
runtime="/me/DR2Runtime"
mkdir "$runtime"
cd "$runtime"
gzip -dc /path/to/DR2Runtime-OPENSTEP42.tar.gz | gnutar xf -
sh build-on-openstep.sh
```

Open the generated `.app` bundles in the runtime's `Apps` directory from Workspace.
Each app starts its private service automatically.
This build of Stickies saves its notes in `~/Library/.StickiesDR2Stack`.
MailViewer uses `~/MailboxesDR2Runtime` and asks for its incoming-mail configuration on first launch.
Project Builder uses OPENSTEP's compiler, makefiles, and debugger.
Its runtime also includes DR2's compiler descriptions, run/debug adaptors, and introductory documentation.
