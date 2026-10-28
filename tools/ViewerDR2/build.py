"""Prepare DR2 Viewer and its compatibility sources for OPENSTEP 4.2 Intel."""

import argparse
import struct
import tarfile
from pathlib import Path

from tools.common.build_dr2 import build_bundle
from .prepare import APP_NAME, BUNDLE_NAME, inputs, install_path, prepare_bundle


def build(source, appsupport, output, archive, destination):
    directory = Path(__file__).parent
    native = {name: directory / name for name in (
        "compat.m", "attributes.m", "desktop.m", "cache.m", "build-on-openstep.sh",
    )}
    for name in (
        "dr2-abi.h", "dr2-abi.m", "dr2-appkit.m", "dr2-paths.m", "dr2-popup.m",
        "viewer.m", "viewer-tool.m", "viewer-open-item.m", "dr2-viewer-service.h",
    ):
        native["common/" + name] = directory.parent / "common" / name
    return build_bundle(
        sources=inputs(source, appsupport), input_roots=(source, appsupport),
        output=output, archive=archive, destination=destination, app_name=APP_NAME,
        prepare=prepare_bundle, native_sources=native,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Stock DR2 Viewer.app")
    parser.add_argument(
        "--appsupport", type=Path, required=True, help="Stock DR2 AppSupport.framework"
    )
    parser.add_argument("--output", type=Path, required=True, help="New ViewerDR2.app directory")
    parser.add_argument("--install-path", required=True, help="Absolute app path on OPENSTEP 4.2")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    archive = args.archive or args.output.parent / "ViewerDR2-OPENSTEP42.tar.gz"
    try:
        app, archive = build(
            args.source, args.appsupport, args.output, archive, args.install_path
        )
    except (OSError, ValueError, KeyError, struct.error, tarfile.TarError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Prepared:", app)
    print("Archive:", archive)
    print("Install at:", install_path(args.install_path, BUNDLE_NAME))
    print("On OPENSTEP 4.2, run sh Compatibility/build-on-openstep.sh inside the installed app.")


if __name__ == "__main__":
    main()
