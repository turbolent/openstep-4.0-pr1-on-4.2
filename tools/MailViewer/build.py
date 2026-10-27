"""Build MailViewerPR1.app for OPENSTEP 4.2 Intel from stock PR1 bundles."""

import argparse
import gzip
import hashlib
import io
import struct
import tarfile
import tempfile
from pathlib import Path

from tools.common import EXECUTABLE_MODE, FILE_MODE, TAR_NAME_SIZE, macho, require
from tools.common.patch_macho import rewrite_libraries

from .prepare import DEFAULT_INSTALL_PATH, inputs, install_path, prepare_bundle

# Helper compiled on OPENSTEP 4.2 Intel, 2026-10-26.
HELPER_SHA256 = {
    "MailViewerCompat.dylib": "1e01cac2104353ad0f8f150ac995e830d3d18c9760eb6f3f0b285356c6758448",
}


def helper_binary(directory, destination):
    directory = Path(directory)
    name = "MailViewerCompat.dylib"
    data = (directory / name).read_bytes()
    require(
        hashlib.sha256(data).hexdigest() == HELPER_SHA256[name],
        "Helper checksum mismatch.",
    )
    require(
        macho.is_intel_image(data, macho.MH_DYLIB),
        "Invalid Intel compatibility library.",
    )
    return rewrite_libraries(
        data, {DEFAULT_INSTALL_PATH + "/" + name: destination + "/" + name}
    )


def app_members(bundle):
    for path in sorted(bundle.rglob("*")):
        if not path.is_file():
            continue
        name = path.relative_to(bundle).as_posix()
        require(not path.is_symlink(), "Unexpected bundle symlink: " + name)
        require(
            len(name.encode("ascii")) < TAR_NAME_SIZE,
            "Path too long for OPENSTEP tar: " + name,
        )
        data = path.read_bytes()
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = EXECUTABLE_MODE if name == "MailViewerPR1" else FILE_MODE
        yield info, data


def build(
    source,
    message,
    nextapps,
    output,
    archive,
    destination=DEFAULT_INSTALL_PATH,
    helpers=None,
):
    destination = install_path(destination)
    sources = inputs(source, message, nextapps)
    output, archive = Path(output).absolute(), Path(archive).absolute()
    for path in (output, archive):
        require(
            not path.exists() and not path.is_symlink(),
            "Output already exists: " + str(path),
        )
    output, archive = output.resolve(), archive.resolve()
    require(
        output.name == "MailViewerPR1.app", "Output must be named MailViewerPR1.app."
    )
    require(
        archive != output and output not in archive.parents,
        "Archive must be outside the app.",
    )
    for target in (output, archive):
        for binary, resources in sources:
            require(
                target != binary.parent
                and binary.parent not in target.parents
                and target not in binary.parents,
                "Outputs must be separate from stock inputs.",
            )
    helper = helper_binary(helpers or Path(__file__).parent / "runtime", destination)
    output.parent.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".mailviewer-build-", dir=output.parent
    ) as staging:
        app = prepare_bundle(
            source, message, nextapps, Path(staging) / "MailViewerPR1.app", destination
        )
        (app / "MailViewerCompat.dylib").write_bytes(helper)
        with tempfile.TemporaryDirectory(
            prefix=".mailviewer-archive-", dir=archive.parent
        ) as packaging:
            packed = Path(packaging) / "mailviewer.tar.gz"
            with (
                packed.open("wb") as raw,
                gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped,
            ):
                with tarfile.open(
                    fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT
                ) as tar:
                    for info, data in app_members(app):
                        tar.addfile(info, io.BytesIO(data))
                    instructions = (
                        "OPENSTEP 4.2 Intel MailViewer PR1\n\nInstall at: "
                        + destination
                        + "\n"
                        "The absolute path is embedded in the executable and private libraries.\n"
                        "This archive contains the CONTENTS of MailViewerPR1.app.\n"
                        "Quit MailViewer PR1 and back up the old bundle. Create the target directory,\n"
                        "cd into it, then run gzip -dc /path/to/archive.tar.gz | tar xf -\n"
                        "Open the resulting bundle from Workspace.\n"
                    ).encode("ascii")
                    info = tarfile.TarInfo("INSTALL.txt")
                    info.size, info.mode = len(instructions), FILE_MODE
                    tar.addfile(info, io.BytesIO(instructions))
            with tarfile.open(packed) as tar:
                for info, data in app_members(app):
                    require(
                        tar.extractfile(info.name).read() == data,
                        "Archive content mismatch: " + info.name,
                    )
                    require(
                        tar.getmember(info.name).mode == info.mode,
                        "Archive mode mismatch: " + info.name,
                    )
            app.rename(output)
            packed.rename(archive)
    return output, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="Stock PR1 MailViewer.app or MailViewer binary",
    )
    parser.add_argument(
        "--message",
        type=Path,
        required=True,
        help="Stock PR1 Message.framework or Message binary",
    )
    parser.add_argument(
        "--nextapps",
        type=Path,
        required=True,
        help="Stock PR1 NeXTApps.framework or NeXTApps binary",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New output directory named MailViewerPR1.app",
    )
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--install-path", default=DEFAULT_INSTALL_PATH)
    parser.add_argument("--helpers-dir", type=Path)
    args = parser.parse_args()
    try:
        app, archive = build(
            args.source,
            args.message,
            args.nextapps,
            args.output,
            args.archive or args.output.parent / "MailViewerPR1-OPENSTEP42.tar.gz",
            args.install_path,
            args.helpers_dir,
        )
    except (OSError, ValueError, KeyError, struct.error, tarfile.TarError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Built:", app)
    print("Archive:", archive)
    print("Install at:", install_path(args.install_path))
    print("Archive SHA256:", hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
