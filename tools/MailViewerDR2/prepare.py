"""Patch stock Rhapsody DR2 Intel images and Interface Builder archives."""

import hashlib
import shutil
import struct
from pathlib import Path, PurePosixPath

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.patch_macho import dylib_command, intel_slice, rewrite_libraries

APP_NAME = "MailViewerDR2"
BUNDLE_NAME = APP_NAME + ".app"
COMPATIBILITY_LIBRARY = "DR2Compat.dylib"
PAGE_SIZE = 4096
LC_SYMTAB = 2
N_TYPE = 0x0E
N_UNDF = 0
N_PBUD = 0x0C
NLIST = struct.Struct("<IBBHI")
OBJC_CLASS = struct.Struct("<10I")
OBJC_IVAR = struct.Struct("<3I")
CLASS_SIZE_OFFSET = 20
IVAR_VALUE_OFFSET = 8
TIFF_HEADER = struct.Struct(">2sHI")
TIFF_DIRECTORY_COUNT = struct.Struct(">H")
TIFF_ENTRY = struct.Struct(">HHII")
TIFF_OFFSET = struct.Struct(">I")
TIFF_MAGIC = 42
TIFF_SHORT = 3
TIFF_LONG = 4
TIFF_INLINE_SHORT_SHIFT = 16
TIFF_IMAGE_WIDTH = 256
TIFF_IMAGE_HEIGHT = 257
APP_ICON_SIZE = 48
SYSTEM_FRAMEWORKS = {"AppKit", "Foundation", "System", "SoundKit"}
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
    value = value.rstrip("/")
    require(
        value.startswith("/") and not value.startswith("//"),
        "Install path must be absolute.",
    )
    require(
        not any(part in (".", "..") for part in value.split("/")),
        "Invalid install path components.",
    )
    require(
        value.isascii() and value.isprintable(),
        "Install path must use printable ASCII.",
    )
    require(
        PurePosixPath(value).name == BUNDLE_NAME,
        "Install path must end in " + BUNDLE_NAME + ".",
    )
    return str(PurePosixPath(value))


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


def load_commands(data):
    offset = macho.MACH_HEADER.size
    count = macho.UINT32.unpack_from(data, macho.MACH_NCMDS_OFFSET)[0]
    for _ in range(count):
        kind, size = macho.LOAD_COMMAND.unpack_from(data, offset)
        require(
            size >= macho.LOAD_COMMAND.size and offset + size <= len(data),
            "Invalid Mach-O load command.",
        )
        yield kind, offset, data[offset : offset + size]
        offset += size


def patch_image(data, destination):
    replacements = {}
    for kind, _, command in load_commands(data):
        if kind not in (macho.LC_LOAD_DYLIB, macho.LC_ID_DYLIB):
            continue
        _, _, offset, *_ = macho.DYLIB_COMMAND.unpack_from(command)
        old = command[offset:].split(b"\0")[0].decode("ascii")
        name = old.rsplit("/", 1)[-1]
        require(
            name in SYSTEM_FRAMEWORKS | PRIVATE_FRAMEWORKS | {"Message"},
            "Unexpected dependency: " + old,
        )
        base = "/NextLibrary/Frameworks" if name in SYSTEM_FRAMEWORKS else destination
        replacements[old] = base + "/" + name + ".framework/" + name
    data = bytearray(
        rewrite_libraries(
            data, replacements,
            [dylib_command(destination + "/" + COMPATIBILITY_LIBRARY)],
        )
    )
    symtab = linkedit = None
    for kind, offset, command in load_commands(data):
        if kind in (macho.LC_LOAD_DYLIB, macho.LC_ID_DYLIB):
            # OPENSTEP's older libraries have lower versions and timestamps.
            struct.pack_into(
                "<3I", data, offset + 12, 0,
                macho.DYLIB_VERSION_1_0, macho.DYLIB_VERSION_1_0,
            )
        elif kind == LC_SYMTAB:
            symtab = offset
        elif kind == macho.LC_SEGMENT and command[8:24].rstrip(b"\0") == b"__LINKEDIT":
            linkedit = offset
    require(symtab is not None and linkedit is not None, "Missing symbol or link-edit table.")
    symoff, count, stroff, strsize = struct.unpack_from("<4I", data, symtab + 8)
    strings = bytearray(data[stroff : stroff + strsize])
    for index in range(count):
        offset = symoff + index * NLIST.size
        string_index, kind, *_ = NLIST.unpack_from(data, offset)
        name = strings[string_index:].split(b"\0", 1)[0].decode("latin1")
        if kind & N_TYPE in (N_UNDF, N_PBUD) and name[1:] in WRAPPED_FUNCTIONS:
            require(name.startswith("_"), "Unexpected C symbol: " + name)
            macho.UINT32.pack_into(data, offset, len(strings))
            strings.extend(("_DR2" + name[1:]).encode("ascii") + b"\0")
    new_offset = len(data)
    data.extend(strings)
    struct.pack_into("<2I", data, symtab + 16, new_offset, len(strings))
    file_offset = macho.UINT32.unpack_from(data, linkedit + 32)[0]
    file_size = len(data) - file_offset
    macho.UINT32.pack_into(data, linkedit + 36, file_size)
    macho.UINT32.pack_into(data, linkedit + 28, macho.align_up(file_size, PAGE_SIZE))
    return data


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


def full_size_icon(data):
    """Keep the stock 48-pixel TIFF representations without re-encoding pixels."""
    require(len(data) >= TIFF_HEADER.size, "Truncated app icon TIFF.")
    byte_order, magic, offset = TIFF_HEADER.unpack_from(data)
    require((byte_order, magic) == (b"MM", TIFF_MAGIC), "Unsupported app icon TIFF.")
    directories, seen = [], set()
    while offset:
        require(
            offset not in seen and offset + TIFF_DIRECTORY_COUNT.size <= len(data),
            "Invalid app icon TIFF directory.",
        )
        seen.add(offset)
        count = TIFF_DIRECTORY_COUNT.unpack_from(data, offset)[0]
        entries = offset + TIFF_DIRECTORY_COUNT.size
        next_link = entries + count * TIFF_ENTRY.size
        require(
            next_link + TIFF_OFFSET.size <= len(data),
            "Truncated app icon TIFF directory.",
        )
        dimensions = {}
        for index in range(count):
            tag, kind, length, value = TIFF_ENTRY.unpack_from(
                data, entries + index * TIFF_ENTRY.size
            )
            if tag in (TIFF_IMAGE_WIDTH, TIFF_IMAGE_HEIGHT):
                require(
                    kind in (TIFF_SHORT, TIFF_LONG) and length == 1,
                    "Unsupported app icon dimensions.",
                )
                dimensions[tag] = (
                    value >> TIFF_INLINE_SHORT_SHIFT if kind == TIFF_SHORT else value
                )
        require(
            set(dimensions) == {TIFF_IMAGE_WIDTH, TIFF_IMAGE_HEIGHT},
            "Missing app icon dimensions.",
        )
        if all(value == APP_ICON_SIZE for value in dimensions.values()):
            directories.append((offset, next_link))
        offset = TIFF_OFFSET.unpack_from(data, next_link)[0]
    require(directories, "App icon has no full-size representation.")
    result = bytearray(data)
    # 4.2 prefers the 16-pixel, 8-bit image over the 48-pixel, 4-bit image.
    # Unlink smaller representations; preserve compressed data and file offsets.
    TIFF_OFFSET.pack_into(result, TIFF_HEADER.size - TIFF_OFFSET.size, directories[0][0])
    for index, (_, next_link) in enumerate(directories):
        following = directories[index + 1][0] if index + 1 < len(directories) else 0
        TIFF_OFFSET.pack_into(result, next_link, following)
    return bytes(result)


def patch_app_icons(bundle):
    executable = bundle / APP_NAME
    data = bytearray(executable.read_bytes())
    sections = [
        section for section in macho.MachO(data).sections
        if section.segment.rstrip(b"\0") == b"__ICON"
        and section.name.rstrip(b"\0") == b"app"
    ]
    require(len(sections) == 1, "Missing or ambiguous embedded app icon.")
    section = sections[0]
    start, end = section.fileoff, section.fileoff + section.size
    data[start:end] = full_size_icon(data[start:end])
    executable.write_bytes(data)
    resource = bundle / "Resources/app.tiff"
    resource.write_bytes(full_size_icon(resource.read_bytes()))


def prepare_bundle(sources, output, destination):
    output.mkdir()
    for bundle, (binary, resources) in sources.items():
        target = output if bundle == "MailViewer.app" else output / bundle
        target.mkdir(exist_ok=True)
        name = APP_NAME if bundle == "MailViewer.app" else binary.name
        data = patch_image(intel_slice(binary.read_bytes()), destination)
        if bundle == "AppSupport.framework":
            data = patch_class_layouts(data)
        (target / name).write_bytes(data)
        (target / name).chmod(EXECUTABLE_MODE)
        shutil.copytree(resources, target / "Resources")
    patch_app_icons(output)
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
