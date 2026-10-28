# Terminal Tiger

This builder ports Intel Mac OS X Tiger's Terminal to OPENSTEP 4.2.
It runs beside the native Terminal as `TerminalTiger.app` with separate preferences.
The compatibility library is compiled from source on OPENSTEP 4.2.

## Usage

Run from the repository root with Python 3.10 or later.
Set `tiger` to an extracted Intel Tiger 10.4.1 build 8B1025 system tree containing
`Applications/Utilities/Terminal.app`, including its `Contents/Resources` directory.
The retail Tiger DVD's PowerPC-only app is not supported.
Keep stock files and generated apps outside the repository.

```sh
tiger="/path/to/Tiger-10.4.1-8B1025"
out="/path/to/patched-apps"
runtime="/LocalApps/TerminalTiger"

python3 -m pip install -r tools/TerminalTiger/requirements.txt
python3 -B tools/build.py terminal-tiger \
  --source "$tiger/Applications/Utilities/Terminal.app" \
  --output "$out/TerminalTiger" \
  --runtime-directory "$runtime"
```

Copy `$out/TerminalTiger/TerminalTiger-source-bundle.tar.gz` to OPENSTEP 4.2
with its Developer tools installed.
Extract it at the exact `--runtime-directory`, then compile the compatibility source:

```sh
runtime="/LocalApps/TerminalTiger"
mkdir "$runtime"
cd "$runtime"

gzip -dc /path/to/TerminalTiger-source-bundle.tar.gz | gnutar xf -
sh build-on-openstep.sh
open "$runtime/TerminalTiger.app"
```

Choose a writable parent directory that already exists.
The app is ready to launch after compilation succeeds.
Keep `TerminalTiger.app` and `TigerCompat.dylib` in the specified runtime directory;
rebuild with a different `--runtime-directory` to relocate them.

Font coverage depends on OPENSTEP's installed fonts.
Antialiasing, transparency, Secure Keyboard Entry, and external AppleScript control
are unavailable.
