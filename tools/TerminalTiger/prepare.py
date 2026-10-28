"""Adapt the verified Tiger Intel Mach-O image to the OPENSTEP loader."""
import hashlib
import struct
from tools.common.patch_macho import intel_slice, dylib_command
from tools.common.macho import MachO

SOURCE_SHA256 = 'e4dc34a97fe790b2ceebb245be5f75828b638b6e0d0fff712bae05b3612279b9'

def prepare(contents, runtime_directory):
    b = bytearray(intel_slice(contents))
    if hashlib.sha256(b).hexdigest() != SOURCE_SHA256:
        raise ValueError('Expected the Intel slice of Terminal 1.5 (133), Tiger 8B1025')
    if not runtime_directory.startswith('/') or '\x00' in runtime_directory:
        raise ValueError('The OPENSTEP runtime directory must be an absolute path')
    REMOTE = runtime_directory.rstrip('/')
    image = MachO(b)
    offset = 28
    commands = []
    for _ in range(struct.unpack_from('<I', b, 16)[0]):
        kind, size = struct.unpack_from('<II', b, offset)
        command = bytearray(b[offset:offset+size])
        if kind == 2:
            symtab = offset
            symoff, count, stroff, strsize = struct.unpack_from('<4I', b, offset + 8)
        if kind == 0xb:
            dysym = struct.unpack_from('<18I', b, offset + 8)
        if kind == 5:
            assert struct.unpack_from('<I', command, 8)[0] == 0xffffffff
            # OPENSTEP and this DTK both use the historical -1 thread flavor.
            # Their user code/data segment selectors differ.
            for index, value in ((8, 0x17), (11, 0x0f), (12, 0x17), (13, 0x17)):
                struct.pack_into('<I', command, 16 + index * 4, value)
        if kind == 1 and command[8:24].rstrip(b'\0') == b'__LINKEDIT':
            linkedit = offset
        if kind not in (12, 0x16):
            commands.append(command)
        offset += size

    # Modify symbols before rebuilding the command table (which changes offsets).
    strings = bytearray(b[stroff:stroff+strsize])
    cf_index = None
    abi_names = {'fprintf','fputc','fflush','popen','pclose','stat','fstat','statfs','getpwuid','getpwnam','setenv','tcgetattr','tcsetattr','ioctl','forkpty','close','NSUnionRect','NSOffsetRect','usleep'}
    for i in range(count):
        position = symoff + 12*i
        strx, kind, section, desc, value = struct.unpack_from('<IBBHI', b, position)
        name = strings[strx:strings.index(0, strx)].decode('latin1')
        if kind & 14 in (0, 12):
            struct.pack_into('<H', b, position + 6, desc & 0xff)
        if name == '___CFConstantStringClassReference':
            cf_index = i
            name = '__NSConstantStringClassReference'
        elif name == '_NSApplicationMain':
            name = '_TigerApplicationMain'
        elif name.startswith('_') and name[1:] in abi_names:
            name = '_Tiger' + name[1:]
        else:
            continue
        struct.pack_into('<I', b, position, len(strings))
        strings.extend(name.encode('ascii') + b'\0')

    extrel, nrel = dysym[14:16]
    constant_count = 0
    for i in range(nrel):
        address, info = struct.unpack_from('<II', b, extrel + 8*i)
        if (info >> 27) & 1 and (info & 0xffffff) == cf_index:
            position = image.offset(address)
            isa, flags, chars, length = struct.unpack_from('<4I', b, position)
            assert flags in (0x7c8, 0x7d0), hex(flags)
            assert flags == 0x7c8, 'UTF-16 constant needs conversion'
            struct.pack_into('<4I', b, position, isa, chars, length, 0)
            constant_count += 1

    # The native dyld binary-searches undefined symbols. Renaming imports must
    # preserve the ordering and remap every relocation and indirect reference.
    first, number = dysym[4:6]
    entries = [(i, bytes(b[symoff+12*i:symoff+12*(i+1)])) for i in range(first, first+number)]
    def symbol_name(entry):
        index = struct.unpack_from('<I', entry[1])[0]
        return strings[index:strings.index(0,index)]
    entries.sort(key=symbol_name)
    mapping = {}
    for new, (old, entry) in enumerate(entries, first):
        mapping[old] = new
        b[symoff+12*new:symoff+12*(new+1)] = entry
    indirect, nindirect = dysym[12:14]
    for i in range(nindirect):
        value = struct.unpack_from('<I',b,indirect+4*i)[0]
        struct.pack_into('<I',b,indirect+4*i,mapping.get(value,value))
    for i in range(nrel):
        position = extrel+8*i+4
        info = struct.unpack_from('<I',b,position)[0]
        if (info>>27)&1:
            struct.pack_into('<I',b,position,(info&0xff000000)|mapping.get(info&0xffffff,info&0xffffff))

    newstroff = len(b)
    b.extend(strings)
    # Update the preserved copies of SYMTAB and LINKEDIT commands.
    for command in commands:
        kind = struct.unpack_from('<I', command)[0]
        if kind == 2:
            struct.pack_into('<2I', command, 16, newstroff, len(strings))
        if kind == 1 and command[8:24].rstrip(b'\0') == b'__LINKEDIT':
            fileoff = struct.unpack_from('<I', command, 32)[0]
            length = len(b) - fileoff
            struct.pack_into('<I', command, 36, length)
            struct.pack_into('<I', command, 28, (length + 4095) & ~4095)
    for name in ('AppKit', 'Foundation', 'System'):
        commands.append(dylib_command('/NextLibrary/Frameworks/' + name + '.framework/' + name))
    commands.append(dylib_command(REMOTE + '/TigerCompat.dylib'))
    # Preserve every code/data virtual address while giving the native loader
    # 8-KiB-aligned file mappings. The header gets a separate read-only mapping.
    HEADER_ADDRESS = 0x68000
    stub = image.offset(0x20d0)
    assert b[stub:stub+5] == b'\x68\x00\x10\x00\x00'
    struct.pack_into('<I', b, stub + 1, HEADER_ADDRESS)
    def file_offset(old):
        return old + (0x1000 if old < 0x54000 else 0x2000)
    for command in commands:
        kind = struct.unpack_from('<I', command)[0]
        if kind == 1:
            name = command[8:24].rstrip(b'\0')
            if name == b'__PAGEZERO':
                struct.pack_into('<I', command, 28, 0x2000)
            elif name == b'__TEXT':
                struct.pack_into('<4I', command, 24, 0x2000, 0x50000, 0x2000, 0x50000)
            else:
                old = struct.unpack_from('<I', command, 32)[0]
                struct.pack_into('<I', command, 32, file_offset(old))
                if name == b'__DATA':
                    struct.pack_into('<I', command, 36, 0x4000)
                elif name == b'__LINKEDIT':
                    struct.pack_into('<I', command, 28, 0x8000)
            nsects = struct.unpack_from('<I', command, 48)[0]
            for i in range(nsects):
                field = 56 + 68*i + 40
                old = struct.unpack_from('<I', command, field)[0]
                if old:
                    struct.pack_into('<I', command, field, file_offset(old))
        elif kind == 2:
            for field in (8, 16):
                struct.pack_into('<I', command, field, file_offset(struct.unpack_from('<I', command, field)[0]))
        elif kind == 0xb:
            for field in (32, 40, 48, 56, 64, 72):
                old = struct.unpack_from('<I', command, field)[0]
                if old:
                    struct.pack_into('<I', command, field, file_offset(old))
    commands.insert(1, bytearray(struct.pack('<II16s8I', 1, 56, b'__HEADER', HEADER_ADDRESS, 0x2000, 0, 0x2000, 7, 1, 0, 4)))
    for i in range(count):
        position = symoff + 12*i
        strx = struct.unpack_from('<I', b, position)[0]
        name = strings[strx:strings.index(0, strx)]
        if name == b'__mh_execute_header':
            struct.pack_into('<I', b, position + 8, HEADER_ADDRESS)
    b = b[:28] + bytes(0x2000-28) + b[0x1000:0x54000] + bytes(0x1000) + b[0x54000:]
    header = b''.join(commands)
    assert 28 + len(header) <= 0x2000
    b[28:28+len(header)] = header
    struct.pack_into('<3I', b, 16, len(commands), len(header), 5)
    return bytes(b)
