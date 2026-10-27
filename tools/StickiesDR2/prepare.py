"""Patch stock Rhapsody DR2 Intel Stickies for OPENSTEP 4.2."""

import hashlib
import shutil
from pathlib import Path

from tools.common import EXECUTABLE_MODE, require
from tools.common.dr2 import install_path, patch_app_icons, patch_image
from tools.common.patch_macho import intel_slice

APP_NAME = "StickiesDR2"
BUNDLE_NAME = APP_NAME + ".app"
STOCK_SHA256 = "5584032789ee99c7d46ae27e1c53de1d226bcc5ab42355444ca3607a82a8251e"
STOCK_DATABASE = ".StickiesDatabase"
PORT_DATABASE = ".StickiesDR2Notes"


def inputs(source):
    source = Path(source).resolve()
    binary = source / "Stickies"
    resources = source / "Resources"
    require(binary.is_file(), "Missing stock Stickies executable: " + str(binary))
    require(
        hashlib.sha256(binary.read_bytes()).hexdigest() == STOCK_SHA256,
        "Unsupported DR2 Stickies executable.",
    )
    require(resources.is_dir(), "Missing stock Resources directory.")
    require(
        (resources / "Info-nextstep.plist").is_file(),
        "Missing stock Info-nextstep.plist.",
    )
    require(
        not any(path.is_symlink() for path in resources.rglob("*")),
        "Resource symlinks are unsupported.",
    )
    require((source / STOCK_DATABASE).is_file(), "Missing stock sample-note database.")
    return source


def prepare_bundle(source, output, destination):
    destination = install_path(destination, BUNDLE_NAME)
    data = patch_image(intel_slice((source / "Stickies").read_bytes()), destination)
    old = STOCK_DATABASE.encode("ascii") + b"\0"
    new = PORT_DATABASE.encode("ascii") + b"\0"
    require(len(old) == len(new) and old in data, "Unexpected Stickies database path.")
    output.mkdir()
    executable = output / APP_NAME
    executable.write_bytes(data.replace(old, new))
    executable.chmod(EXECUTABLE_MODE)
    shutil.copytree(source / "Resources", output / "Resources")
    shutil.copyfile(source / STOCK_DATABASE, output / PORT_DATABASE)
    info = (output / "Resources/Info-nextstep.plist").read_bytes()
    info = info.replace(b"= Stickies;", b"= StickiesDR2;")
    info = info.replace(b'"Make Sticky"', b'"Make DR2 Sticky"')
    for name in ("Info.plist", "Info-nextstep.plist"):
        (output / "Resources" / name).write_bytes(info)
    for path in output.rglob("objects.nib"):
        path.write_bytes(path.read_bytes().replace(b"ssii@@@@@", b"ssIi@@@@@"))
    patch_app_icons(output, APP_NAME, "Stickies.tiff")
    return output
