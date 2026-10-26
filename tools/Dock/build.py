"""Build a complete OPENSTEP 4.2 Intel DockPR1.app from stock PR1 Workspace."""

import argparse
import gzip
import hashlib
import io
import struct
import tarfile
import tempfile
from pathlib import Path

from tools.common import EXECUTABLE_MODE, FILE_MODE, macho, require
from tools.common.macho import MachO

from .prepare import (
    DEFAULT_INSTALL_PATH,
    EXPECTED,
    add_app_to_tar,
    install_path,
    prepare_bundle,
    source_files,
)

# Helpers compiled and tested on OPENSTEP 4.2 Intel, 2026-10-25.
HELPER_SHA256 = {
    "PR1Compat.dylib": "70fbd793bb767c0ef987eb7b8b3426258e0a573aeb38f1f5728e8466a803b1aa",
    "OpenItem": "e5bbe8e54a3973ff1470aa18f9f708874f7363d85e7343ea0dcfa41b5207867d",
}
# Retain the compiled Dock helper's eight-byte dylib-command alignment.
HELPER_DYLIB_ALIGNMENT = 8


def helper_binaries(directory):
    result = {}
    for name, filetype in (
        ("PR1Compat.dylib", macho.MH_DYLIB),
        ("OpenItem", macho.MH_EXECUTE),
    ):
        data = (directory / name).read_bytes()
        expected = HELPER_SHA256[name]
        require(
            hashlib.sha256(data).hexdigest() == expected,
            "Helper checksum mismatch: " + name,
        )
        require(
            macho.is_intel_image(data, filetype),
            "Wrong helper architecture or file type: " + name,
        )
        result[name] = data
    return result


def relocate_library(data, destination):
    """Change LC_ID_DYLIB within header slack, leaving every section at its offset."""
    wanted = (destination + "/PR1Compat.dylib").encode("ascii") + b"\0"
    ncmds, old_size = macho.MACH_COMMAND_COUNTS.unpack_from(
        data, macho.MACH_NCMDS_OFFSET
    )
    commands, offset, found = [], macho.MACH_HEADER.size, False
    for _ in range(ncmds):
        command, size = macho.LOAD_COMMAND.unpack_from(data, offset)
        require(
            size >= macho.LOAD_COMMAND.size
            and offset + size <= macho.MACH_HEADER.size + old_size,
            "Invalid helper load command.",
        )
        block = data[offset : offset + size]
        if command == macho.LC_ID_DYLIB:
            require(
                not found and size >= macho.DYLIB_COMMAND.size,
                "Invalid helper library identity.",
            )
            found = True
            _, _, name_offset, timestamp, current, compatibility = (
                macho.DYLIB_COMMAND.unpack_from(block)
            )
            require(
                macho.DYLIB_COMMAND.size <= name_offset < size,
                "Invalid library name offset.",
            )
            old_name = block[name_offset:].split(b"\0")[0]
            if old_name == wanted[:-1]:
                commands.append(block)
                offset += size
                continue
            new_size = macho.align_up(
                macho.DYLIB_COMMAND.size + len(wanted), HELPER_DYLIB_ALIGNMENT
            )
            header = macho.DYLIB_COMMAND.pack(
                command,
                new_size,
                macho.DYLIB_COMMAND.size,
                timestamp,
                current,
                compatibility,
            )
            block = header + wanted.ljust(new_size - macho.DYLIB_COMMAND.size, b"\0")
        commands.append(block)
        offset += size
    require(found, "Helper has no LC_ID_DYLIB.")
    replacement = b"".join(commands)
    image = MachO(data)
    first_section = min(
        section.fileoff for section in image.sections if section.fileoff
    )
    commands_end = macho.MACH_HEADER.size + max(old_size, len(replacement))
    require(
        commands_end <= first_section,
        "Install path exceeds helper Mach-O header space.",
    )
    result = bytearray(data)
    result[macho.MACH_HEADER.size : commands_end] = replacement.ljust(
        max(old_size, len(replacement)), b"\0"
    )
    macho.UINT32.pack_into(result, macho.MACH_SIZEOFCMDS_OFFSET, len(replacement))
    return bytes(result)


def build(
    source,
    output,
    archive,
    destination=DEFAULT_INSTALL_PATH,
    resources=None,
    helpers=None,
):
    destination = install_path(destination)
    binary, resource_dir = source_files(source, resources)
    output, archive = Path(output).absolute(), Path(archive).absolute()
    require(
        not output.exists() and not output.is_symlink(),
        "Output already exists: " + str(output),
    )
    require(
        not archive.exists() and not archive.is_symlink(),
        "Archive already exists: " + str(archive),
    )
    output, archive = output.resolve(), archive.resolve()
    require(output.name == "DockPR1.app", "Output directory must be named DockPR1.app.")
    require(
        output != archive and output not in archive.parents,
        "Archive must be outside the app.",
    )
    protected = [resource_dir]
    if Path(source).is_dir() or binary.parent.suffix == ".app":
        protected.append(binary.parent)
    for target in (output, archive):
        require(
            target != binary
            and all(p != target and p not in target.parents for p in protected)
            and target not in binary.parents
            and target not in resource_dir.parents,
            "Build output must be separate from the stock source.",
        )
    # All input checks happen before creating output directories or copying resources.
    require(
        hashlib.sha256(binary.read_bytes()).hexdigest() == EXPECTED,
        "Unsupported Workspace binary; only the stock PR1 multi-architecture binary is supported.",
    )
    runtime = helper_binaries(
        Path(helpers) if helpers else Path(__file__).parent / "runtime"
    )
    runtime["PR1Compat.dylib"] = relocate_library(
        runtime["PR1Compat.dylib"], destination
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".dock-build-", dir=output.parent
    ) as staging:
        bundle = prepare_bundle(
            binary, Path(staging) / "DockPR1.app", destination, resource_dir
        )
        for name, data in runtime.items():
            (bundle / name).write_bytes(data)
            (bundle / name).chmod(EXECUTABLE_MODE if name == "OpenItem" else FILE_MODE)
        # Fixed tar metadata and gzip timestamp make repeated builds byte-identical.
        with tempfile.TemporaryDirectory(
            prefix=".dock-archive-", dir=archive.parent
        ) as packaging:
            packed = Path(packaging) / "DockPR1.tar.gz"
            with packed.open("wb") as raw:
                with gzip.GzipFile(
                    filename="", mode="wb", fileobj=raw, mtime=0
                ) as zipped:
                    with tarfile.open(
                        fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT
                    ) as tar:
                        add_app_to_tar(tar, bundle)
                        instructions = (
                            "OPENSTEP 4.2 Intel Dock PR1\n\n"
                            "Install DockPR1.app at: " + destination + "\n"
                            "This absolute path is embedded in the executable and helper.\n"
                            "Quit an existing Dock PR1 before replacing its bundle.\n"
                            "Open DockPR1.app from Workspace. Run one copy per account.\n"
                        ).encode("ascii")
                        info = tarfile.TarInfo("INSTALL.txt")
                        info.size, info.mode = len(instructions), FILE_MODE
                        tar.addfile(info, io.BytesIO(instructions))
            # Verify packaged files and modes before publishing either output.
            with tarfile.open(packed, "r:gz") as tar:
                for path in bundle.rglob("*"):
                    if path.is_file():
                        name = "DockPR1.app/" + path.relative_to(bundle).as_posix()
                        require(
                            tar.extractfile(name).read() == path.read_bytes(),
                            "Archive verification failed.",
                        )
                require(
                    tar.getmember("DockPR1.app/DockPR1").mode == EXECUTABLE_MODE,
                    "Executable mode missing.",
                )
            bundle.rename(output)
            packed.rename(archive)
    return output, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="Stock Workspace.app folder or its Workspace binary",
    )
    parser.add_argument(
        "--resources", type=Path, help="Resources folder, if not beside the binary"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New output directory named DockPR1.app",
    )
    parser.add_argument(
        "--archive", type=Path, help="New .tar.gz file (default: beside output app)"
    )
    parser.add_argument(
        "--install-path",
        default=DEFAULT_INSTALL_PATH,
        help="Final absolute path on OPENSTEP",
    )
    parser.add_argument(
        "--helpers-dir",
        type=Path,
        help="Directory containing the verified compiled helpers",
    )
    args = parser.parse_args()
    archive = args.archive or args.output.parent / "DockPR1-OPENSTEP42.tar.gz"
    try:
        bundle, archive = build(
            args.source,
            args.output,
            archive,
            args.install_path,
            args.resources,
            args.helpers_dir,
        )
    except (OSError, ValueError, KeyError, struct.error, tarfile.TarError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Built:", bundle)
    print("Archive:", archive)
    print("Install at:", install_path(args.install_path))
    print("Archive SHA256:", hashlib.sha256(archive.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
