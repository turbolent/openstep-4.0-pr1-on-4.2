"""Patch stock Rhapsody DR2 Intel MailViewer for OPENSTEP 4.2."""

import hashlib
import shutil
import struct
from pathlib import Path

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.dr2 import (
    install_path as validate_install_path,
    patch_app_icons,
    patch_image,
)
from tools.common.patch_macho import intel_slice

APP_NAME = "MailViewerDR2"
BUNDLE_NAME = APP_NAME + ".app"
OBJC_CLASS = struct.Struct("<10I")
OBJC_IVAR = struct.Struct("<3I")
CLASS_SIZE_OFFSET = 20
IVAR_VALUE_OFFSET = 8
PRIVATE_FRAMEWORKS = {"MailViewer", "AppSupport", "HTML"}
WRAPPED_FUNCTIONS = {
    "fopen", "fdopen", "fclose", "fread", "fwrite", "fprintf", "fputc", "fputs",
    "setbuf", "stat", "fstat", "connect",
}
STOCK_HASHES = {
    "MailViewer.app": "ee3dc00e5d408484ffb7879449d3d2d554f1546f4a22e1ef99f24a03a8edcd90",
    "MailViewer.framework": "d17db3fe9ef693b0c7ce6f03d3288cce4ca291bcc6bf9962ea3be23b405b8213",
    "Message.framework": "fab91dc2ad510b055c4722e938b0ab728c764b1e35f6b12f7e92af83e5ac305a",
    "AppSupport.framework": "ff763cffaaa0a38d8cacc6cc0ad24c942a82393cc95d1af4e5a3cca02428095c",
    "HTML.framework": "0ee4566910c674608b81e78fa1e078f0008fd3fc8d8c28d9ee92aa920e484cb3",
}

# OPENSTEP's superclass instances are larger than their DR2 counterparts.
# Update both Objective-C metadata and the compiled subclass field accesses.
CLASS_LAYOUTS = {
    "NSIconPopUpButton": (100, 108, (96,), (104,)),
    "DocumentMenuItem": (72, 76, (64, 68), (68, 72)),
}
FIELD_OPERANDS = (
    (96, 104, (
        0x49A05F62, 0x49A05F8C, 0x49A05F95, 0x49A0600B,
        0x49A06039, 0x49A06053, 0x49A0615F,
    )),
    (64, 68, (0x49A0C40C, 0x49A0C459, 0x49A0C46F, 0x49A0C484)),
)


def install_path(value):
    return validate_install_path(value, BUNDLE_NAME)


def inputs(source, frameworks):
    source, frameworks = Path(source).resolve(), Path(frameworks).resolve()
    bundles = {"MailViewer.app": source}
    for name in ("MailViewer", "Message", "AppSupport", "HTML"):
        directory = "PrivateFrameworks" if name in PRIVATE_FRAMEWORKS else "Frameworks"
        bundles[name + ".framework"] = frameworks / directory / (name + ".framework")
    result = {}
    for bundle, root in bundles.items():
        name = bundle.split(".")[0]
        binary = root / name
        if not binary.is_file():
            version = "A" if name == "HTML" else "B"
            binary = root / "Versions" / version / name
        require(binary.is_file(), "Missing stock input: " + str(binary))
        require(
            hashlib.sha256(binary.read_bytes()).hexdigest() == STOCK_HASHES[bundle],
            "Unsupported DR2 input: " + str(binary),
        )
        resources = binary.parent / "Resources"
        if not resources.is_dir():
            resources = root / "Resources"
        require(resources.is_dir(), "Missing stock Resources directory: " + str(resources))
        require(
            not any(path.is_symlink() for path in resources.rglob("*")),
            "Resource symlinks are unsupported.",
        )
        result[bundle] = binary, resources
    require(
        (result["MailViewer.app"][1] / "Info-nextstep.plist").is_file(),
        "Missing MailViewer Info-nextstep.plist.",
    )
    return result


def patch_class_layouts(data):
    image = macho.MachO(data)
    found = set()
    for section in image.sections:
        if section.name.rstrip(b"\0") != b"__class":
            continue
        for offset in range(section.fileoff, section.fileoff + section.size, OBJC_CLASS.size):
            fields = OBJC_CLASS.unpack_from(data, offset)
            name_offset = image.offset(fields[2])
            name = data[name_offset : data.index(0, name_offset)].decode("ascii")
            if name not in CLASS_LAYOUTS:
                continue
            old_size, new_size, old_fields, new_fields = CLASS_LAYOUTS[name]
            require(fields[5] == old_size, "Unexpected class size: " + name)
            macho.UINT32.pack_into(data, offset + CLASS_SIZE_OFFSET, new_size)
            ivars = image.offset(fields[6])
            require(
                macho.UINT32.unpack_from(data, ivars)[0] == len(old_fields),
                "Unexpected instance variables: " + name,
            )
            for index, (old, new) in enumerate(zip(old_fields, new_fields)):
                field = ivars + macho.UINT32.size + index * OBJC_IVAR.size + IVAR_VALUE_OFFSET
                require(
                    macho.UINT32.unpack_from(data, field)[0] == old,
                    "Unexpected instance variable offset: " + name,
                )
                macho.UINT32.pack_into(data, field, new)
            found.add(name)
    require(found == set(CLASS_LAYOUTS), "Missing AppSupport classes.")
    for old, new, addresses in FIELD_OPERANDS:
        for address in addresses:
            offset = image.offset(address)
            require(data[offset] == old, "Unexpected field operand at " + hex(address))
            data[offset] = new
    return data


def prepare_bundle(sources, output, destination):
    output.mkdir()
    for bundle, (binary, resources) in sources.items():
        target = output if bundle == "MailViewer.app" else output / bundle
        target.mkdir(exist_ok=True)
        name = APP_NAME if bundle == "MailViewer.app" else binary.name
        data = patch_image(
            intel_slice(binary.read_bytes()), destination,
            PRIVATE_FRAMEWORKS | {"Message"}, WRAPPED_FUNCTIONS,
        )
        if bundle == "AppSupport.framework":
            data = patch_class_layouts(data)
        (target / name).write_bytes(data)
        (target / name).chmod(EXECUTABLE_MODE)
        shutil.copytree(resources, target / "Resources")
    patch_app_icons(output, APP_NAME, "app.tiff")
    info = (output / "Resources/Info-nextstep.plist").read_bytes()
    for key in (b"NSExecutable", b"NSPortName"):
        info = info.replace(key + b" = MailViewer;", key + b" = MailViewerDR2;")
    for name in ("Info.plist", "Info-nextstep.plist"):
        (output / "Resources" / name).write_bytes(info)
    # DR2 writes an unsigned NSCell flags word; 4.2 requests a signed word.
    for path in output.rglob("objects.nib"):
        path.write_bytes(path.read_bytes().replace(b"ssii@@@@@", b"ssIi@@@@@"))
    for relative in (
        "Resources/MailViewer.defaults",
        "Message.framework/Resources/Message.defaults",
    ):
        path = output / relative
        defaults = path.read_bytes()
        for old, new in (
            (b'MailDir = "~/Mailboxes";', b'MailDir = "~/MailboxesDR2";'),
            (b'SpoolDir = "/var/mail";', b'SpoolDir = "/usr/spool/mail";'),
            (b'Mailer = "/usr/sbin/sendmail";', b'Mailer = "/usr/lib/sendmail";'),
        ):
            require(old in defaults, "Unexpected DR2 mail defaults: " + relative)
            defaults = defaults.replace(old, new)
        path.write_bytes(defaults)
    return output
