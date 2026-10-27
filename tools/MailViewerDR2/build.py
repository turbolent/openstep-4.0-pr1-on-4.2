"""Prepare DR2 MailViewer and its compatibility sources for OPENSTEP 4.2 Intel."""

import argparse
import gzip
import io
import shutil
import struct
import tarfile
import tempfile
from pathlib import Path

from tools.common import EXECUTABLE_MODE, FILE_MODE, require

from .prepare import APP_NAME, BUNDLE_NAME, inputs, install_path, prepare_bundle

NATIVE_SOURCES = ("abi.m", "compat.m", "undo.m", "build-on-openstep.sh")


def package(bundle, archive):
    with archive.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(
                fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT
            ) as tar:
                for path in sorted(bundle.rglob("*")):
                    if not path.is_file():
                        continue
                    name = path.relative_to(bundle).as_posix()
                    info = tarfile.TarInfo(name)
                    data = path.read_bytes()
                    info.size = len(data)
                    info.mode = EXECUTABLE_MODE if name == APP_NAME else FILE_MODE
                    tar.addfile(info, io.BytesIO(data))


def build(source, frameworks, output, archive, destination):
    destination = install_path(destination)
    sources = inputs(source, frameworks)
    output, archive = Path(output).absolute(), Path(archive).absolute()
    for target in (output, archive):
        require(
            not target.exists() and not target.is_symlink(),
            "Output already exists: " + str(target),
        )
    output, archive = output.resolve(), archive.resolve()
    require(output.name == BUNDLE_NAME, "Output must be named " + BUNDLE_NAME + ".")
    require(
        output not in archive.parents and archive != output,
        "Archive must be outside the app.",
    )
    for root in (Path(source).resolve(), Path(frameworks).resolve()):
        for target in (output, archive):
            require(
                root != target
                and root not in target.parents
                and target not in root.parents,
                "Outputs must be separate from stock inputs.",
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".mailviewer-dr2-", dir=output.parent
    ) as staging:
        app = prepare_bundle(sources, Path(staging) / BUNDLE_NAME, destination)
        native = app / "Compatibility"
        native.mkdir()
        for name in NATIVE_SOURCES:
            shutil.copyfile(Path(__file__).parent / name, native / name)
        # The native compiler checks this path before creating the dylib.
        (native / "install-path").write_text(
            destination + "\n", encoding="ascii", newline="\n"
        )
        with tempfile.TemporaryDirectory(
            prefix=".mailviewer-dr2-", dir=archive.parent
        ) as packed:
            temporary_archive = Path(packed) / "app.tar.gz"
            package(app, temporary_archive)
            app.rename(output)
            temporary_archive.rename(archive)
    return output, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", type=Path, required=True, help="Stock DR2 MailViewer.app"
    )
    parser.add_argument(
        "--frameworks",
        type=Path,
        required=True,
        help="DR2 System/Library containing Frameworks and PrivateFrameworks",
    )
    parser.add_argument(
        "--output", type=Path, required=True, help="New MailViewerDR2.app directory"
    )
    parser.add_argument(
        "--install-path", required=True, help="Absolute app path on OPENSTEP 4.2"
    )
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    archive = args.archive or args.output.parent / "MailViewerDR2-OPENSTEP42.tar.gz"
    try:
        app, archive = build(
            args.source, args.frameworks, args.output, archive, args.install_path
        )
    except (OSError, ValueError, KeyError, struct.error, tarfile.TarError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Prepared:", app)
    print("Archive:", archive)
    print("Install at:", install_path(args.install_path))
    print(
        "On OPENSTEP 4.2, run sh Compatibility/build-on-openstep.sh "
        "inside the installed app."
    )


if __name__ == "__main__":
    main()
