"""Checked PR1 binary patches; prepare a bundle for native helper compilation."""

import argparse
import hashlib
import shutil
import tarfile
from pathlib import Path, PurePosixPath

from tools.common import EXECUTABLE_MODE, FILE_MODE, macho, require
from tools.common.macho import MachO
from tools.common.patch_macho import (
    add_app_icon,
    dylib_command,
    intel_slice,
    rewrite_libraries,
)

EXPECTED = "1d6a84c0593d5ca1848fb1393ef069682218755204f1b3d948229612336c8a75"
DEFAULT_INSTALL_PATH = "/me/Apps/DockPR1.app"
LOGIN_SETUP_CHECK_ADDRESS = 0x327F2
LOGIN_SETUP_END_ADDRESS = 0x32841
CALLER_LOGIN_BRANCH_ADDRESS = 0x329E8
WORKSPACE_REGISTRATION_CALL_ADDRESS = 0x32BDA
LOGIN_SETUP_CHECK = bytes.fromhex("83bb82d5040000")
CALLER_LOGIN_BRANCH = bytes.fromhex("7509")
CALLER_LOGIN_JUMP = bytes.fromhex("eb09")
WORKSPACE_REGISTRATION_CALL = bytes.fromhex("e8c52c0400")
INFO = b"""{
    NSExecutable = DockPR1;
    NSIcon = Workspace.tiff;
    NSPrincipalClass = Workspace;
}
"""


def install_path(value):
    value = value.rstrip("/")
    require(
        value.startswith("/") and not value.startswith("//"),
        "Install path must be an absolute OPENSTEP path.",
    )
    require(
        ".." not in value.split("/") and "." not in value.split("/"),
        "Install path must not contain . or .. components.",
    )
    require(
        value.isascii() and value.isprintable(),
        "Install path must use printable ASCII.",
    )
    require(
        PurePosixPath(value).name == "DockPR1.app",
        "Install path must end in DockPR1.app.",
    )
    return str(PurePosixPath(value))


def source_files(source, resources=None):
    source = Path(source).resolve()
    binary = source / "Workspace" if source.is_dir() else source
    resources = Path(resources).resolve() if resources else binary.parent / "Resources"
    require(binary.is_file(), "Stock Workspace binary not found: " + str(binary))
    require(resources.is_dir(), "Resources folder required: " + str(resources))
    for name in (
        "Workspace.tiff",
        "English.lproj/Workspace.strings",
        "DefaultTabs/General.wtab/Items",
    ):
        require(
            (resources / name).is_file(), "Stock Resources/" + name + " is required."
        )
    require(
        not any(p.is_symlink() for p in resources.rglob("*")),
        "Resources must contain regular files and directories, not symbolic links.",
    )
    return binary, resources


def patch_binary(original, icon, destination=DEFAULT_INSTALL_PATH):
    destination = install_path(destination)
    digest = hashlib.sha256(original).hexdigest()
    require(
        digest == EXPECTED,
        "Unsupported Workspace binary. Expected stock PR1 SHA256 "
        + EXPECTED
        + "; got "
        + digest,
    )
    data = bytearray(intel_slice(original))
    image = MachO(data)

    def patch(address, expected, replacement):
        offset = image.offset(address)
        require(
            data[offset : offset + len(expected)] == expected,
            "Unexpected bytes at " + hex(address),
        )
        require(len(expected) == len(replacement), "Instruction patch length mismatch.")
        data[offset : offset + len(expected)] = replacement

    # Skip login-manager setup and run as the caller.
    jump = macho.X86_JUMP_REL32 + macho.INT32.pack(
        LOGIN_SETUP_END_ADDRESS
        - (LOGIN_SETUP_CHECK_ADDRESS + macho.X86_REL32_INSTRUCTION_SIZE)
    )
    patch(
        LOGIN_SETUP_CHECK_ADDRESS,
        LOGIN_SETUP_CHECK,
        jump.ljust(len(LOGIN_SETUP_CHECK), macho.X86_NOP),
    )
    patch(CALLER_LOGIN_BRANCH_ADDRESS, CALLER_LOGIN_BRANCH, CALLER_LOGIN_JUMP)
    patch(
        WORKSPACE_REGISTRATION_CALL_ADDRESS,
        WORKSPACE_REGISTRATION_CALL,
        macho.X86_NOP * len(WORKSPACE_REGISTRATION_CALL),
    )
    old = b"/NextLibrary/Frameworks/AppKit.framework/Versions/A/AppKit"
    new = b"/NextLibrary/Frameworks/AppKit.framework/Versions/B/AppKit"
    require(data.count(old) == 1, "Unexpected AppKit dependency.")
    data = data.replace(old, new)

    first_section = min(
        section.fileoff for section in image.sections if section.fileoff
    )
    for section in image.sections:
        require(
            not section.relocation_offset
            or section.relocation_offset >= first_section,
            "Header overlaps relocation data.",
        )
    data = rewrite_libraries(
        data, {}, [dylib_command(destination + "/PR1Compat.dylib")]
    )
    return add_app_icon(data, "DockPR1", icon)


def prepare_bundle(source, output, destination=DEFAULT_INSTALL_PATH, resources=None):
    binary, resources = source_files(source, resources)
    output = Path(output).resolve()
    require(output.name == "DockPR1.app", "Output directory must be named DockPR1.app.")
    require(
        not output.exists(),
        "Output already exists; choose a new directory: " + str(output),
    )
    require(
        output != binary
        and output not in binary.parents
        and resources not in output.parents
        and resources != output
        and output not in resources.parents
        and (binary.parent.suffix != ".app" or binary.parent not in output.parents),
        "Output must be separate from the source bundle.",
    )
    data = patch_binary(
        binary.read_bytes(), (resources / "Workspace.tiff").read_bytes(), destination
    )
    output.mkdir(parents=True)
    shutil.copytree(resources, output / "Resources")
    (output / "DockPR1").write_bytes(data)
    (output / "DockPR1").chmod(EXECUTABLE_MODE)
    for name in ("Info.plist", "Info-nextstep.plist"):
        (output / "Resources" / name).write_bytes(INFO)
    return output


def add_app_to_tar(archive, bundle):
    for path in sorted(bundle.rglob("*")):
        if path.is_file():
            info = archive.gettarinfo(
                str(path), "DockPR1.app/" + path.relative_to(bundle).as_posix()
            )
            info.mode = (
                EXECUTABLE_MODE if path.name in ("DockPR1", "OpenItem") else FILE_MODE
            )
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ""
            with path.open("rb") as source:
                archive.addfile(info, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        required=True,
        help="Stock PR1 Workspace.app or Workspace binary",
    )
    parser.add_argument(
        "--resources", type=Path, help="Resources folder when not next to the binary"
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="New output directory named DockPR1.app",
    )
    parser.add_argument("--install-path", default=DEFAULT_INSTALL_PATH)
    parser.add_argument(
        "--archive", type=Path, help="New .tar file (default: beside output app)"
    )
    args = parser.parse_args()
    archive = args.archive or args.output.parent / "dock-install-input.tar"
    try:
        require(
            not archive.exists(), "Archive already exists: " + str(archive)
        )
        bundle = prepare_bundle(
            args.source, args.output, args.install_path, args.resources
        )
        archive.parent.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive, "w", format=tarfile.USTAR_FORMAT) as output_archive:
            add_app_to_tar(output_archive, bundle)
    except (ValueError, OSError) as error:
        parser.exit(1, "Error: " + str(error) + "\n")
    print("Prepared", bundle)
    print("Install at", install_path(args.install_path))
    print(
        "Compile PR1Compat.dylib and OpenItem using build-on-openstep.sh before running."
    )


if __name__ == "__main__":
    main()
