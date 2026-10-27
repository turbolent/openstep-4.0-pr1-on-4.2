"""Prepare DR2 Stickies and its compatibility sources for OPENSTEP 4.2 Intel."""

import argparse
import struct
import tarfile
from pathlib import Path

from tools.common.build_dr2 import build_bundle
from .prepare import APP_NAME, inputs, prepare_bundle


def build(source, output, archive, destination):
    directory = Path(__file__).parent
    native = {name: directory / name for name in ("compat.m", "build-on-openstep.sh")}
    for name in ("dr2-appkit.m", "dr2-paths.m"):
        native["common/" + name] = directory.parent / "common" / name
    return build_bundle(
        sources=inputs(source), input_roots=(source,), output=output, archive=archive,
        destination=destination, app_name=APP_NAME, prepare=prepare_bundle,
        native_sources=native,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Stock DR2 Stickies.app")
    parser.add_argument("--output", type=Path, required=True, help="New StickiesDR2.app directory")
    parser.add_argument("--install-path", required=True, help="Absolute app path on OPENSTEP 4.2")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    archive = args.archive or args.output.parent / "StickiesDR2-OPENSTEP42.tar.gz"
    try:
        app, archive = build(args.source, args.output, archive, args.install_path)
    except (OSError, ValueError, KeyError, struct.error, tarfile.TarError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Prepared:", app)
    print("Archive:", archive)
    print("Install at:", args.install_path.rstrip("/"))
    print("On OPENSTEP 4.2, run sh Compatibility/build-on-openstep.sh inside the installed app.")


if __name__ == "__main__":
    main()
