"""Prepare DR2 Workspace's Applications menu for OPENSTEP 4.2."""

import hashlib
import shutil
from pathlib import Path

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.dr2 import WRAPPED_FUNCTIONS, install_path, patch_app_icons, patch_image

APP_NAME = "WorkspaceDR2"
BUNDLE_NAME = APP_NAME + ".app"
STOCK_HASH = "9cf0c9d9dccfbc0b1787d3199e0370248cd23046494935afb969e0b0260fbcbf"
MAIN_ADDRESS = 0x3EE0
MAIN_PROLOGUE = bytes.fromhex("5589e583ec04575653")
DEFAULTS_LOAD_ADDRESS = 0x3E70
DEFAULTS_LOAD_PROLOGUE = bytes.fromhex("5589e55653")
ENTRY_STUB_ADDRESS = 0x2ADD4
X86_RETURN = b"\xc3"


def inputs(source):
    source = Path(source).resolve()
    binary = source / "Workspace"
    require(binary.is_file(), "Missing stock Workspace executable.")
    require(
        hashlib.sha256(binary.read_bytes()).hexdigest() == STOCK_HASH,
        "Unsupported DR2 Workspace executable.",
    )
    require((source / "Resources").is_dir(), "Missing stock Resources directory.")
    require(
        not any(path.is_symlink() for path in source.rglob("*")),
        "Resource symlinks are unsupported.",
    )
    return source


def patch_binary(data, destination):
    data = patch_image(
        data,
        destination,
        wrapped_functions=WRAPPED_FUNCTIONS,
        symbol_replacements={"_setsid": "_WorkspaceDR2Main"},
    )
    image = macho.MachO(data)
    for address, original, replacement in (
        (
            MAIN_ADDRESS,
            MAIN_PROLOGUE,
            macho.X86_JUMP_REL32 + macho.INT32.pack(
                ENTRY_STUB_ADDRESS - MAIN_ADDRESS - macho.X86_REL32_INSTRUCTION_SIZE
            ),
        ),
        (DEFAULTS_LOAD_ADDRESS, DEFAULTS_LOAD_PROLOGUE, X86_RETURN),
    ):
        offset = image.offset(address)
        require(
            data[offset : offset + len(original)] == original,
            "Unexpected Workspace startup code at " + hex(address),
        )
        data[offset : offset + len(replacement)] = replacement
    # Keep Listener's native service registration instead of DR2's category.
    require(data.count(b"checkInAs:\0") == 1, "Unexpected Listener category.")
    data = data.replace(b"checkInAs:\0", b"dr2Unused:\0")
    icon_header = next(
        section
        for section in image.sections
        if section.segment.rstrip(b"\0") == b"__ICON"
        and section.name.rstrip(b"\0") == b"__header"
    )
    header = f"F\t{BUNDLE_NAME}\t{APP_NAME}\tapp\n".encode("ascii")
    require(len(header) < icon_header.size, "App name exceeds embedded icon header.")
    data[icon_header.fileoff : icon_header.fileoff + icon_header.size] = header.ljust(
        icon_header.size, b"\0"
    )
    return data


def prepare_bundle(source, output, destination):
    destination = install_path(destination, BUNDLE_NAME)
    output.mkdir()
    resources = output / "Resources"
    shutil.copytree(source / "Resources", resources)
    # Disk and console tools belong to the session manager, not this menu app.
    for name in ("disktool", "kernelpanel.tool"):
        (resources / name).unlink()
    executable = output / APP_NAME
    executable.write_bytes(patch_binary((source / "Workspace").read_bytes(), destination))
    executable.chmod(EXECUTABLE_MODE)
    patch_app_icons(output, APP_NAME, "Apple.tiff")
    info = (
        "{\n    NSExecutable = WorkspaceDR2;\n    NSPortName = WorkspaceDR2;\n"
        "    NSIcon = Apple.tiff;\n    NSPrincipalClass = NSApplication;\n}\n"
    )
    for name in ("Info.plist", "Info-nextstep.plist"):
        (resources / name).write_text(info, encoding="ascii", newline="\n")
    return output
