"""Adapt DR2 Mach-O images and icons to OPENSTEP 4.2."""

import struct
from pathlib import PurePosixPath

from . import macho, require
from .patch_macho import dylib_command, rewrite_libraries

WRAPPED_FUNCTIONS = {
    "fopen", "fdopen", "fclose", "fread", "fwrite", "fprintf", "fputc", "fputs",
    "setbuf", "stat", "fstat", "connect",
}

PAGE_SIZE = 4096
LC_SYMTAB = 2
LC_DYSYMTAB = 11
INDIRECT_SYMBOL_SPECIAL = 0xC0000000
RELOCATION_EXTERNAL = 0x08000000
RELOCATION_SCATTERED = 0x80000000
SYMBOL_INDEX_MASK = 0x00FFFFFF
RELOCATION = struct.Struct("<2I")
N_TYPE = 0x0E
N_UNDF = 0
N_PBUD = 0x0C
NLIST = struct.Struct("<IBBHI")
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
COMPATIBILITY_LIBRARY = "DR2Compat.dylib"


def install_path(value, bundle_name):
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
        PurePosixPath(value).name == bundle_name,
        "Install path must end in " + bundle_name + ".",
    )
    return str(PurePosixPath(value))


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


def patch_image(data, destination, frameworks=(), wrapped_functions=()):
    replacements = {}
    for kind, _, command in load_commands(data):
        if kind not in (macho.LC_LOAD_DYLIB, macho.LC_ID_DYLIB):
            continue
        _, _, offset, *_ = macho.DYLIB_COMMAND.unpack_from(command)
        old = command[offset:].split(b"\0")[0].decode("ascii")
        name = old.rsplit("/", 1)[-1]
        require(
            name in SYSTEM_FRAMEWORKS | set(frameworks),
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
        if kind & N_TYPE in (N_UNDF, N_PBUD) and name[1:] in wrapped_functions:
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
    sort_undefined_symbols(data)
    return data


def sort_undefined_symbols(data):
    """Keep dyld's sorted imports and all their symbol indexes in agreement."""
    symtab = dynamic = None
    for kind, _, command in load_commands(data):
        if kind == LC_SYMTAB:
            symtab = struct.unpack_from("<4I", command, 8)
        elif kind == LC_DYSYMTAB:
            dynamic = struct.unpack_from("<18I", command, 8)
    if dynamic is None:
        return
    require(symtab is not None, "Missing symbol table.")
    symoff, _, stroff, strsize = symtab
    first, count = dynamic[4:6]
    strings = data[stroff : stroff + strsize]
    entries = []
    for index in range(first, first + count):
        offset = symoff + index * NLIST.size
        entry = bytes(data[offset : offset + NLIST.size])
        name_offset = macho.UINT32.unpack_from(entry)[0]
        name = strings[name_offset : strings.index(0, name_offset)]
        entries.append((name, index, entry))
    entries.sort(key=lambda entry: entry[0])
    indexes = {old: first + index for index, (_, old, _) in enumerate(entries)}
    for index, (_, _, entry) in enumerate(entries):
        offset = symoff + (first + index) * NLIST.size
        data[offset : offset + NLIST.size] = entry

    indirect_offset, indirect_count = dynamic[12:14]
    for offset in range(indirect_offset, indirect_offset + indirect_count * macho.UINT32.size, macho.UINT32.size):
        index = macho.UINT32.unpack_from(data, offset)[0]
        if not index & INDIRECT_SYMBOL_SPECIAL:
            macho.UINT32.pack_into(data, offset, indexes.get(index, index))

    relocations = set()
    external_offset, external_count = dynamic[14:16]
    relocations.update(range(external_offset, external_offset + external_count * RELOCATION.size, RELOCATION.size))
    for section in macho.MachO(data).sections:
        relocations.update(range(
            section.relocation_offset,
            section.relocation_offset + section.relocation_count * RELOCATION.size,
            RELOCATION.size,
        ))
    for offset in relocations:
        address, info = RELOCATION.unpack_from(data, offset)
        if address & RELOCATION_SCATTERED or not info & RELOCATION_EXTERNAL:
            continue
        index = info & SYMBOL_INDEX_MASK
        info = (info & ~SYMBOL_INDEX_MASK) | indexes.get(index, index)
        macho.UINT32.pack_into(data, offset + macho.UINT32.size, info)

    references_offset, references_count = dynamic[10:12]
    for offset in range(references_offset, references_offset + references_count * macho.UINT32.size, macho.UINT32.size):
        reference = macho.UINT32.unpack_from(data, offset)[0]
        index = reference & SYMBOL_INDEX_MASK
        reference = (reference & ~SYMBOL_INDEX_MASK) | indexes.get(index, index)
        macho.UINT32.pack_into(data, offset, reference)


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


def patch_app_icons(bundle, app_name, resource_name):
    executable = bundle / app_name
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
    resource = bundle / "Resources" / resource_name
    resource.write_bytes(full_size_icon(resource.read_bytes()))
