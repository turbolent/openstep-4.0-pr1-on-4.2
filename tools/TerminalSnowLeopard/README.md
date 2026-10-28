# Terminal Snow Leopard

This builder ports Mac OS X Snow Leopard's Terminal to OPENSTEP 4.2.
It runs beside the native Terminal as `TerminalSnowLeopard.app` with separate preferences.
The compatibility library is compiled from source on OPENSTEP 4.2.
Each shell opens in its own window; tabs are not supported.

## Usage

Run from the repository root with Python 3.10 or later.
Set `snow` to an extracted Snow Leopard system tree containing
`Applications/Utilities/Terminal.app`, updated to Mac OS X 10.6.8,
including its `Contents/Resources` directory.
The builder verifies the executable's checksum.
Keep stock files and generated apps outside the repository.

```sh
snow="/path/to/Snow-Leopard-10.6.8"
out="/path/to/patched-apps"
runtime="/LocalApps/TerminalSnowLeopard"

python3 -m pip install -r tools/TerminalSnowLeopard/requirements.txt
python3 -B tools/build.py terminal-snow-leopard \
  --source "$snow/Applications/Utilities/Terminal.app" \
  --output "$out/TerminalSnowLeopard" \
  --runtime-directory "$runtime"
```

The builder downloads verified PCRE sources for text searches. For an offline build,
add `--pcre-archive /path/to/pcre-8.45.tar.bz2`.

Copy `$out/TerminalSnowLeopard/TerminalSnowLeopard-source-bundle.tar.gz` to OPENSTEP 4.2
with its Developer tools installed and at least 128 MiB of free disk space.
Extract it at the exact `--runtime-directory`, then compile:

```sh
runtime="/LocalApps/TerminalSnowLeopard"
mkdir "$runtime"
cd "$runtime"

gzip -dc /path/to/TerminalSnowLeopard-source-bundle.tar.gz | gnutar xf -
sh build-on-openstep.sh
open "$runtime/TerminalSnowLeopard.app"
```

Choose a writable parent directory that already exists.
Keep `TerminalSnowLeopard.app` and `SnowCompat.dylib` in the specified runtime directory;
rebuild with a different `--runtime-directory` to relocate them.

Font coverage depends on OPENSTEP's installed fonts.
Antialiasing, window transparency, Secure Keyboard Entry, Dictionary lookup, Terminal Help,
and external AppleScript control are unavailable. Word selection uses Unicode's default boundaries;
dictionary-based segmentation is unavailable.
