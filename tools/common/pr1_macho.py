"""Mach-O edits shared by PR1 ports; keep section addresses and offsets intact."""

from . import macho, require
from .macho import MachO


def intel_slice(data):
    if data.startswith(macho.FAT_MAGIC):
        _, architecture_count = macho.FAT_HEADER.unpack_from(data)
        for index in range(architecture_count):
            cpu, _, offset, size, _ = macho.FAT_ARCH.unpack_from(
                data, macho.FAT_HEADER.size + index * macho.FAT_ARCH.size
            )
            if cpu == macho.CPU_TYPE_I386:
                require(offset + size <= len(data), "Truncated Intel slice.")
                return data[offset : offset + size]
        raise ValueError("No Intel architecture.")
    require(macho.is_intel_image(data), "Expected an Intel Mach-O image.")
    return data


def dylib_command(
    path,
    command=macho.LC_LOAD_DYLIB,
    versions=(macho.DYLIB_VERSION_1_0, macho.DYLIB_VERSION_1_0),
):
    name = path.encode("ascii") + b"\0"
    size = macho.align_up(macho.DYLIB_COMMAND.size + len(name), macho.UINT32.size)
    header = macho.DYLIB_COMMAND.pack(
        command, size, macho.DYLIB_COMMAND.size, 0, *versions
    )
    return header + name.ljust(size - macho.DYLIB_COMMAND.size, b"\0")


def rewrite_libraries(data, replacements, extra=(), remove=()):
    image = MachO(data)
    count, old_size = macho.MACH_COMMAND_COUNTS.unpack_from(
        data, macho.MACH_NCMDS_OFFSET
    )
    commands, offset = [], macho.MACH_HEADER.size
    for _ in range(count):
        kind, size = macho.LOAD_COMMAND.unpack_from(data, offset)
        block = data[offset : offset + size]
        if kind in (macho.LC_LOAD_DYLIB, macho.LC_ID_DYLIB):
            _, _, name_offset, _, current, compatibility = (
                macho.DYLIB_COMMAND.unpack_from(block)
            )
            name = block[name_offset:].split(b"\0")[0].decode("ascii")
            if kind == macho.LC_LOAD_DYLIB and name in remove:
                offset += size
                continue
            if name in replacements:
                block = dylib_command(
                    replacements[name], kind, (current, compatibility)
                )
        commands.append(block)
        offset += size
    commands.extend(extra)
    replacement = b"".join(commands)
    first_section = min(
        section.fileoff for section in image.sections if section.fileoff
    )
    commands_end = macho.MACH_HEADER.size + max(old_size, len(replacement))
    require(
        commands_end <= first_section,
        "Insufficient Mach-O header space.",
    )
    result = bytearray(data)
    result[macho.MACH_HEADER.size : commands_end] = replacement.ljust(
        max(old_size, len(replacement)), b"\0"
    )
    macho.MACH_COMMAND_COUNTS.pack_into(
        result, macho.MACH_NCMDS_OFFSET, len(commands), len(replacement)
    )
    return bytes(result)


def add_app_icon(data, name, icon):
    image = MachO(data)
    require(
        not any(
            segment.name.rstrip(b"\0") == b"__ICON" for segment in image.segments
        ),
        "Image already has __ICON.",
    )
    header = ("F\t%s.app\t%s\tapp\nF\t%s\t%s\tapp\n" % (name, name, name, name)).encode(
        "ascii"
    )
    header += b"\0" * (-len(header) % macho.UINT32.size)
    content = header + icon
    vm = macho.align_up(
        max(segment.vmaddr + segment.vmsize for segment in image.segments),
        macho.ICON_SEGMENT_ALIGNMENT,
    )
    offset = macho.align_up(len(data), macho.ICON_SEGMENT_ALIGNMENT)
    size = macho.align_up(len(content), macho.ICON_SEGMENT_ALIGNMENT)
    sections = (
        (b"__header", vm, len(header), offset),
        (b"app", vm + len(header), len(icon), offset + len(header)),
    )
    segment = macho.SEGMENT_COMMAND.pack(
        macho.LC_SEGMENT,
        macho.SEGMENT_COMMAND.size + len(sections) * macho.SECTION.size,
        b"__ICON",
        vm,
        size,
        offset,
        size,
        macho.VM_PROT_READ,
        macho.VM_PROT_READ,
        len(sections),
        macho.SG_NORELOC,
    )
    for section, address, length, fileoff in sections:
        segment += macho.SECTION.pack(
            section,
            b"__ICON",
            address,
            length,
            fileoff,
            macho.SECTION_ALIGNMENT_POWER,
            0,
            0,
            macho.S_REGULAR,
            0,
            0,
        )
    data = rewrite_libraries(data, {}, [segment])
    return data.ljust(offset, b"\0") + content.ljust(size, b"\0")
