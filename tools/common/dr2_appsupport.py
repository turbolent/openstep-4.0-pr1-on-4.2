"""Adapt DR2 AppSupport subclasses to OPENSTEP 4.2 instance layouts."""

import struct

from . import macho, require

OBJC_CLASS = struct.Struct("<10I")
OBJC_IVAR = struct.Struct("<3I")
CLASS_SIZE_OFFSET = 20
IVAR_VALUE_OFFSET = 8

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
