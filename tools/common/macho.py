"""Read the Mach-O segments and sections used by the patchers."""

import struct
from collections import namedtuple
from pathlib import Path

UINT32 = struct.Struct("<I")
INT32 = struct.Struct("<i")
MACH_HEADER = struct.Struct("<7I")
MACH_COMMAND_COUNTS = struct.Struct("<2I")
FAT_HEADER = struct.Struct(">2I")
FAT_ARCH = struct.Struct(">5I")
LOAD_COMMAND = struct.Struct("<2I")
DYLIB_COMMAND = struct.Struct("<6I")
SEGMENT_COMMAND = struct.Struct("<II16s8I")
SECTION = struct.Struct("<16s16s9I")

MACH_MAGIC_I386 = b"\xce\xfa\xed\xfe"
FAT_MAGIC = b"\xca\xfe\xba\xbe"
CPU_TYPE_I386 = 7
MH_EXECUTE = 2
MH_DYLIB = 6
LC_SEGMENT = 1
LC_LOAD_DYLIB = 12
LC_ID_DYLIB = 13
MACH_NCMDS_OFFSET = UINT32.size * 4
MACH_SIZEOFCMDS_OFFSET = UINT32.size * 5
DYLIB_VERSION_1_0 = 0x10000
ICON_SEGMENT_ALIGNMENT = 8192
SECTION_ALIGNMENT_POWER = 2
VM_PROT_READ = 1
SG_NORELOC = 4
S_REGULAR = 0
X86_NOP = b"\x90"
X86_JUMP_REL32 = b"\xe9"
X86_REL32_INSTRUCTION_SIZE = 1 + INT32.size

Segment = namedtuple(
    "Segment", "name vmaddr vmsize fileoff filesize maxprot initprot nsects flags"
)
Section = namedtuple(
    "Section",
    "name segment address size fileoff alignment relocation_offset "
    "relocation_count flags reserved1 reserved2",
)


def align_up(value, alignment):
    return (value + alignment - 1) // alignment * alignment


def is_intel_image(data, filetype=None):
    if len(data) < MACH_HEADER.size or not data.startswith(MACH_MAGIC_I386):
        return False
    _, cpu, _, kind, _, _, _ = MACH_HEADER.unpack_from(data)
    return cpu == CPU_TYPE_I386 and (filetype is None or kind == filetype)


class MachO:
    def __init__(self, source):
        self.contents = (
            bytes(source)
            if isinstance(source, (bytes, bytearray))
            else Path(source).read_bytes()
        )
        self.segments = []
        self.sections = []
        offset = MACH_HEADER.size
        command_count = UINT32.unpack_from(self.contents, MACH_NCMDS_OFFSET)[0]

        for _ in range(command_count):
            command, size = LOAD_COMMAND.unpack_from(self.contents, offset)
            if command == LC_SEGMENT:
                _, _, *fields = SEGMENT_COMMAND.unpack_from(self.contents, offset)
                segment = Segment(*fields)
                self.segments.append(segment)
                for index in range(segment.nsects):
                    section = Section(
                        *SECTION.unpack_from(
                            self.contents,
                            offset + SEGMENT_COMMAND.size + index * SECTION.size,
                        )
                    )
                    self.sections.append(section)
            offset += size

    def offset(self, address):
        for segment in self.segments:
            if segment.vmaddr <= address < segment.vmaddr + segment.filesize:
                return address - segment.vmaddr + segment.fileoff
        raise ValueError(hex(address))

