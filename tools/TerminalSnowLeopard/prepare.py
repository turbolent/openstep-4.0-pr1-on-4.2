"""Translate Snow Leopard's fixed-address i386 image for the OPENSTEP dyld."""

import hashlib
import struct

from tools.common.macho import MachO
from tools.common.patch_macho import dylib_command, intel_slice
from tools.TerminalTiger.build import ABI_NAMES

SOURCE_SHA256 = '998e22272f462ef7e6bb838af13ba56fe646e182342794303e97c1a5cefc3c03'
HEADER_ADDRESS = 0x100000


def bindings(data, segments, lazy=False):
    """Decode dyld's bytecode into (address, symbol, addend) records."""
    cursor = 0
    address = 0
    symbol = None
    addend = 0
    kind = 1

    def leb(signed=False):
        nonlocal cursor
        value = shift = 0
        while True:
            byte = data[cursor]
            cursor += 1
            value |= (byte & 127) << shift
            shift += 7
            if not byte & 128:
                return value - (1 << shift) if signed and byte & 64 else value

    while cursor < len(data):
        byte = data[cursor]
        cursor += 1
        opcode, immediate = byte & 0xf0, byte & 15
        if opcode == 0:
            if not lazy:
                break
            addend, kind = 0, 1
        elif opcode in (0x10, 0x30):
            pass  # Flat namespace on OPENSTEP.
        elif opcode == 0x20:
            leb()
        elif opcode == 0x40:
            end = data.index(0, cursor)
            symbol = data[cursor:end].decode('ascii')
            cursor = end + 1
        elif opcode == 0x50:
            kind = immediate
        elif opcode == 0x60:
            addend = leb(signed=True)
        elif opcode == 0x70:
            address = segments[immediate].vmaddr + leb()
        elif opcode == 0x80:
            address += leb()
        elif opcode in (0x90, 0xa0, 0xb0, 0xc0):
            if kind != 1 or symbol is None:
                raise ValueError('Expected a named 32-bit pointer binding')
            count, skip = (leb(), leb()) if opcode == 0xc0 else (1, 0)
            for _ in range(count):
                yield address, symbol, addend
                address += 4 + skip
            if opcode == 0xa0:
                address += leb()
            elif opcode == 0xb0:
                address += immediate * 4
        else:
            raise ValueError('Unsupported dyld binding opcode %02x' % byte)


def import_name(name):
    if name == '___CFConstantStringClassReference':
        return '__NSConstantStringClassReference'
    if name == '_NSApplicationMain':
        return '_SnowApplicationMain'
    if name == '_NSShowSystemInfoPanel':
        return '_SnowShowSystemInfoPanel'
    if name == '_NSRectFillUsingOperation':
        return '_SnowNSRectFillUsingOperation'
    if name == 'dyld_stub_binder':
        return '_SnowUnexpectedLazyBinding'
    name = name.replace('$UNIX2003', '')
    if name in ('_stat$INODE64', '_statfs$INODE64'):
        return '_Snow' + name[1:].replace('$INODE64', '64')
    if name == '_fwrite':
        return '_Snowfwrite'
    if name == '_fgets':
        return '_Snowfgets'
    if name == '_setenv':
        return '_Snowsetenv'
    if name in ('__setjmp', '_NSInsetRect', '_NSIntegralRect', '_NSDrawTiledRects'):
        return '_Snow' + name[1:]
    if name.startswith('_') and name[1:] in ABI_NAMES:
        return '_Tiger' + name[1:]
    return name


def prepare(contents, runtime_directory):
    b = bytearray(intel_slice(contents))
    if hashlib.sha256(b).hexdigest() != SOURCE_SHA256:
        raise ValueError('Expected Terminal from the Snow Leopard 10.6.8 update')
    if not runtime_directory.startswith('/') or '\x00' in runtime_directory:
        raise ValueError('The OPENSTEP runtime directory must be an absolute path')
    image = MachO(b)
    commands = []
    offset = 28
    for _ in range(struct.unpack_from('<I', b, 16)[0]):
        kind, size = struct.unpack_from('<II', b, offset)
        command = bytearray(b[offset:offset + size])
        if kind == 0x80000022:
            rebase, rebase_size, bind, bind_size, weak, weak_size, lazy, lazy_size, _, _ = struct.unpack_from('<10I', command, 8)
            if rebase_size or weak_size:
                raise ValueError('Unexpected rebasing or weak bindings in fixed executable')
        elif kind == 2:
            symoff, count, stroff, strsize = struct.unpack_from('<4I', command, 8)
            symtab = command
        elif kind == 11:
            dysym = command
        elif kind == 5:
            flavor, count_state = struct.unpack_from('<II', command, 8)
            assert (flavor, count_state) == (1, 16)
            command.extend(bytes(4))
            struct.pack_into('<3I', command, 4, 84, 0xffffffff, 17)
            for index, value in ((8, 0x17), (11, 0x0f), (12, 0x17), (13, 0x17)):
                struct.pack_into('<I', command, 16 + index * 4, value)
        if kind in (1, 2, 11, 14, 5):
            if kind == 1 and command[8:24].rstrip(b'\0') == b'__DATA':
                # Native _dyld_present() tests the main image's __dyld
                # section before registering Objective-C image callbacks.
                # The modern executable has no such section. This unused
                # tail of its data mapping holds the native loader hooks.
                assert not any(b[0x7ef00:0x7ef14])
                command.extend(struct.pack('<16s16s9I', b'__dyld', b'__DATA',
                                           0x7ff00, 20, 0x7ef00, 2, 0, 0, 0, 0, 0))
                struct.pack_into('<I', command, 4, len(command))
                struct.pack_into('<I', command, 48, struct.unpack_from('<I', command, 48)[0]+1)
            commands.append(command)
        offset += size

    imports = list(bindings(b[bind:bind + bind_size], image.segments))
    imports += list(bindings(b[lazy:lazy + lazy_size], image.segments, lazy=True))
    old_strings = b[stroff:stroff + strsize]
    strings = bytearray(b'\0')
    symbols = []
    first, number = struct.unpack_from('<II', dysym, 24)
    for i in range(count):
        strx, kind, section, desc, value = struct.unpack_from('<IBBHI', b, symoff + i * 12)
        name = old_strings[strx:old_strings.index(0, strx)].decode('ascii')
        name = import_name(name)
        if name == '__mh_execute_header':
            value = HEADER_ADDRESS
        symbols.append((i, name, kind, section, desc & 0xff, value))
    symbols[first:first + number] = sorted(symbols[first:first + number], key=lambda s: s[1])
    mapping, by_name = {}, {}
    for index, (old, name, kind, section, desc, value) in enumerate(symbols):
        mapping[old] = index
        by_name[name] = index
        struct.pack_into('<IBBHI', b, symoff + index * 12, len(strings), kind, section, desc, value)
        strings.extend(name.encode('ascii') + b'\0')
    indirect, nindirect = struct.unpack_from('<II', dysym, 56)
    for i in range(nindirect):
        value = struct.unpack_from('<I', b, indirect + i * 4)[0]
        struct.pack_into('<I', b, indirect + i * 4, mapping.get(value, value))

    relocations = bytearray()
    for address, name, addend in imports:
        position = image.offset(address)
        if name == '___CFConstantStringClassReference':
            _, flags, chars, length = struct.unpack_from('<4I', b, position)
            if flags == 0x7d0:
                # The only UTF-16 constant is a single nonbreaking space. Its
                # Mac Roman byte fits in the original three-byte allocation.
                start = image.offset(chars)
                value = b[start:start + length * 2].decode('utf-16-le').encode('mac_roman')
                b[start:start + len(value) + 1] = value + b'\0'
                length = len(value)
            elif flags != 0x7c8:
                raise ValueError('Unknown CF string encoding %x' % flags)
            struct.pack_into('<4I', b, position, 0, chars, length, 0)
        struct.pack_into('<I', b, position, addend & 0xffffffff)
        relocations.extend(struct.pack('<II', address, by_name[import_name(name)] | (2 << 25) | (1 << 27)))
    while len(b) % 4:
        b.append(0)
    extrel = len(b)
    b.extend(relocations)
    struct.pack_into('<II', dysym, 64, extrel, len(imports))
    struct.pack_into('<II', symtab, 16, len(b), len(strings))
    b.extend(strings)

    # Preserve virtual addresses and put all mappings on OPENSTEP's 8 KiB
    # boundaries. Eager external relocations replace compressed lazy binding.
    for section in image.sections:
        if section.name.rstrip(b'\0') == b'__protocol':
            # OPENSTEP's compiler emits version 2 Protocol records. Cocoa
            # uses this word for an optional-method extension pointer (or
            # zero); the remaining five-word prefix has the native layout.
            if section.size % 20:
                raise ValueError('Unexpected Objective-C protocol layout')
            for position in range(section.fileoff, section.fileoff + section.size, 20):
                struct.pack_into('<I', b, position, 2)
        if section.name.rstrip(b'\0') == b'__cls_refs':
            for position in range(section.fileoff, section.fileoff + section.size, 4):
                start = image.offset(struct.unpack_from('<I', b, position)[0])
                if b[start:start + 9] == b'NSThread\0':
                    # Keep application thread handles separate from native
                    # NSThread objects, whose dealloc drains the current
                    # thread's pools and must run on their owning thread.
                    b[start:start + 8] = b'SNThread'
        if section.name.rstrip(b'\0') == b'__class':
            for position in range(section.fileoff, section.fileoff + section.size, 48):
                name_address = struct.unpack_from('<I', b, position + 8)[0]
                start = image.offset(name_address)
                name = b[start:b.index(0, start)]
                if name == b'TTProfileMenuItem':
                    # No application ivars; native NSMenuItem is four bytes larger.
                    struct.pack_into('<I', b, position + 20, 68)
        if section.name.rstrip(b'\0') == b'__program_vars':
            assert struct.unpack_from('<I', b, section.fileoff)[0] == 0x1000
            struct.pack_into('<I', b, section.fileoff, HEADER_ADDRESS)
    for command in commands:
        kind = struct.unpack_from('<I', command)[0]
        if kind == 1:
            name = command[8:24].rstrip(b'\0')
            if name == b'__PAGEZERO':
                struct.pack_into('<I', command, 28, 0x2000)
            elif name == b'__TEXT':
                struct.pack_into('<4I', command, 24, 0x2000, 0x78000, 0x2000, 0x78000)
            else:
                fileoff = struct.unpack_from('<I', command, 32)[0]
                struct.pack_into('<I', command, 32, fileoff + 0x1000)
                if name == b'__LINKEDIT':
                    length = len(b) - fileoff
                    struct.pack_into('<I', command, 28, (length + 8191) & ~8191)
                    struct.pack_into('<I', command, 36, length)
                    assert 0x8c000 + length < HEADER_ADDRESS
            for i in range(struct.unpack_from('<I', command, 48)[0]):
                field = 56 + i * 68
                fileoff = struct.unpack_from('<I', command, field + 40)[0]
                if fileoff:
                    struct.pack_into('<I', command, field + 40, fileoff + 0x1000)
                flags = struct.unpack_from('<I', command, field + 56)[0]
                if flags & 255 in (6, 7):
                    # These pointers are covered by the external relocations;
                    # the old dyld must not overwrite them with lazy helpers.
                    struct.pack_into('<I', command, field + 56, flags & ~255)
        elif kind in (2, 11):
            for field in ((8, 16) if kind == 2 else (32, 40, 48, 56, 64, 72)):
                old = struct.unpack_from('<I', command, field)[0]
                if old:
                    struct.pack_into('<I', command, field, old + 0x1000)
    commands.insert(1, bytearray(struct.pack('<II16s8I', 1, 56, b'__HEADER', HEADER_ADDRESS, 0x2000, 0, 0x2000, 7, 1, 0, 4)))
    for name in ('AppKit', 'Foundation', 'System'):
        commands.append(dylib_command('/NextLibrary/Frameworks/' + name + '.framework/' + name))
    commands.append(dylib_command(runtime_directory.rstrip('/') + '/SnowCompat.dylib'))
    b = b[:28] + bytes(0x2000 - 28) + b[0x1000:]
    header = b''.join(commands)
    assert 28 + len(header) <= 0x2000
    b[28:28 + len(header)] = header
    struct.pack_into('<3I', b, 16, len(commands), len(header), 5)
    return bytes(b)
