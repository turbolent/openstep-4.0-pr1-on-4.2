"""Build ViewerPR1.app for OPENSTEP 4.2 Intel from stock PR1 inputs."""

import argparse
import gzip
import hashlib
import io
import struct
import tarfile
import tempfile
from pathlib import Path

from tools.common import (
    EXECUTABLE_MODE,
    FILE_MODE,
    SYMLINK_MODE,
    TAR_NAME_SIZE,
    macho,
    require,
)
from tools.common.patch_macho import rewrite_libraries

from .prepare import ALIASES, DEFAULT_INSTALL_PATH, inputs, install_path, prepare_bundle

# Helpers compiled from this repository's sources on OPENSTEP 4.2 Intel.
HELPER_SHA256 = {
    "ViewerCompat.dylib": "c13d5f18a70b729e7419bfc2f3f2ac9f1de404063396e97bd7d73d9bcb44eb9a",
    "ToolCompat.dylib": "ac5cb6d4ae4f460a9eeccc25b1772c71ef2be84b7aa59b267f7b879ea9e625f8",
    "OpenItem": "0644daff96a6c7493ce45dc93f7cf1d65c684633833f73d2d068ab7453b3f81b",
}


def helper_binaries(directory, destination):
    directory = Path(directory)
    result = {}
    for name, kind in (
        ("ViewerCompat.dylib", macho.MH_DYLIB),
        ("ToolCompat.dylib", macho.MH_DYLIB),
        ("OpenItem", macho.MH_EXECUTE),
    ):
        data = (directory / name).read_bytes()
        require(
            hashlib.sha256(data).hexdigest() == HELPER_SHA256[name],
            "Helper checksum mismatch: " + name,
        )
        require(
            macho.is_intel_image(data, kind),
            "Invalid Intel helper: " + name,
        )
        if kind == macho.MH_DYLIB:
            data = rewrite_libraries(
                data, {DEFAULT_INSTALL_PATH + "/" + name: destination + "/" + name}
            )
        result[name] = data
    return result


def app_members(bundle):
    for path in sorted(bundle.rglob("*")):
        relative = path.relative_to(bundle)
        if relative.parts[0] in ALIASES or not path.is_file():
            continue
        data = path.read_bytes()
        # OPENSTEP /bin/tar ignores USTAR's path-prefix field. Store app contents
        # without a bundle prefix so every name fits its legacy name field.
        name = relative.as_posix()
        require(
            len(name.encode("ascii")) < TAR_NAME_SIZE,
            "Path too long for OPENSTEP tar: " + name,
        )
        info = tarfile.TarInfo(name)
        info.size = len(data)
        executable = name == "search" or macho.is_intel_image(data, macho.MH_EXECUTE)
        info.mode = EXECUTABLE_MODE if executable else FILE_MODE
        yield info, data
    for name in ALIASES:
        info = tarfile.TarInfo(name)
        info.type, info.linkname, info.mode = (
            tarfile.SYMTYPE,
            "Resources/" + name,
            SYMLINK_MODE,
        )
        yield info, None


def build(
    source, nextapps, output, archive, destination=DEFAULT_INSTALL_PATH, helpers=None
):
    destination = install_path(destination)
    binary, resources, framework, framework_resources = inputs(source, nextapps)
    output, archive = Path(output).absolute(), Path(archive).absolute()
    for path in (output, archive):
        require(
            not path.exists() and not path.is_symlink(),
            "Output already exists: " + str(path),
        )
    output, archive = output.resolve(), archive.resolve()
    require(output.name == "ViewerPR1.app", "Output must be named ViewerPR1.app.")
    require(
        archive != output and output not in archive.parents,
        "Archive must be outside app.",
    )
    for target in (output, archive):
        for original in (binary.parent, framework.parent):
            require(
                target != original
                and original not in target.parents
                and target not in original.parents,
                "Outputs must be separate from stock inputs.",
            )
    runtime = helper_binaries(helpers or Path(__file__).parent / "runtime", destination)
    output.parent.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".viewer-build-", dir=output.parent
    ) as staging:
        app = prepare_bundle(
            source, nextapps, Path(staging) / "ViewerPR1.app", destination
        )
        for name, data in runtime.items():
            (app / name).write_bytes(data)
        (app / "OpenItem").chmod(EXECUTABLE_MODE)
        with tempfile.TemporaryDirectory(
            prefix=".viewer-archive-", dir=archive.parent
        ) as packaging:
            packed = Path(packaging) / "viewer.tar.gz"
            with (
                packed.open("wb") as raw,
                gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as zipped,
            ):
                with tarfile.open(
                    fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT
                ) as tar:
                    for info, data in app_members(app):
                        tar.addfile(
                            info, io.BytesIO(data) if data is not None else None
                        )
                    instructions = (
                        "OPENSTEP 4.2 Intel Viewer PR1\n\nInstall at: "
                        + destination
                        + "\n"
                        "The absolute path is embedded in its executable, plug-ins and libraries.\n"
                        "This archive contains the CONTENTS of ViewerPR1.app.\n"
                        "Quit Viewer PR1 and back up the old bundle. Create the target directory,\n"
                        "cd into it, then run gzip -dc /path/to/archive.tar.gz | tar xf -\n"
                        "Open the resulting bundle from Workspace.\n"
                        "Use the native 4.2 Workspace for disk administration.\n"
                    ).encode("ascii")
                    info = tarfile.TarInfo("INSTALL.txt")
                    info.size, info.mode = len(instructions), FILE_MODE
                    tar.addfile(info, io.BytesIO(instructions))
            with tarfile.open(packed) as tar:
                for info, data in app_members(app):
                    actual = tar.getmember(info.name)
                    if data is not None:
                        require(
                            tar.extractfile(actual).read() == data,
                            "Archive content mismatch: " + info.name,
                        )
                    else:
                        require(
                            actual.issym() and actual.linkname == info.linkname,
                            "Archive alias mismatch.",
                        )
                require(
                    tar.getmember("ViewerPR1").mode == EXECUTABLE_MODE,
                    "Missing executable permission.",
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
        help="Stock Viewer.app bundle or Viewer binary",
    )
    parser.add_argument(
        "--nextapps",
        type=Path,
        required=True,
        help="Stock PR1 NeXTApps.framework folder or its binary",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New output directory named ViewerPR1.app",
    )
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--install-path", default=DEFAULT_INSTALL_PATH)
    parser.add_argument("--helpers-dir", type=Path)
    args = parser.parse_args()
    try:
        app, archive = build(
            args.source,
            args.nextapps,
            args.output,
            args.archive or args.output.parent / "ViewerPR1-OPENSTEP42.tar.gz",
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
