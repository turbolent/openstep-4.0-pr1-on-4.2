"""Check the compiled Unicode shim against standard normalization vectors.

Pass a host-built shared library; this does not require the Apple executable.
"""
import ctypes as c
import random
import sys
import unicodedata


def check(path):
    library = c.CDLL(path)
    unit = c.c_ushort
    library.u_charType.restype = c.c_byte
    library.u_isMirrored.restype = c.c_byte
    library.unorm_isNormalized.restype = c.c_byte
    library.unorm_normalize.argtypes = [c.POINTER(unit), c.c_int, c.c_int, c.c_int, c.POINTER(unit), c.c_int, c.POINTER(c.c_int)]
    library.unorm_isNormalized.argtypes = [c.POINTER(unit), c.c_int, c.c_int, c.POINTER(c.c_int)]
    library.u_strFromUTF8Lenient.argtypes = [c.POINTER(unit), c.c_int, c.POINTER(c.c_int), c.c_char_p, c.c_int, c.POINTER(c.c_int)]
    library.u_strFromUTF8Lenient.restype = c.POINTER(unit)
    library.utf8_nextCharSafeBody.argtypes = [c.c_char_p, c.POINTER(c.c_int), c.c_int, c.c_int, c.c_byte]
    library.utf8_back1SafeBody.argtypes = [c.c_char_p, c.c_int, c.c_int]
    for text in ('', 'ABC', '\u00e9', '\u4e00', '\U0001f600', 'a\0b', '\ud7ff\ue000\U0010ffff'):
        data = text.encode('utf-8')
        expected = text.encode('utf-16-le')
        needed = len(expected)//2
        for capacity in range(needed+2):
            storage = (unit * (capacity+2))(*([0xa55a]*(capacity+2)))
            result = c.cast(c.byref(storage, 2), c.POINTER(unit))
            status, count = c.c_int(), c.c_int()
            library.u_strFromUTF8Lenient(result, capacity, c.byref(count), data, len(data), c.byref(status))
            assert storage[0] == storage[capacity+1] == 0xa55a
            assert count.value == needed
            assert status.value == (15 if needed > capacity else -124 if needed == capacity else 0)
            assert bytes(storage)[2:2+min(needed, capacity)*2] == expected[:capacity*2]
            if capacity > needed:
                assert result[needed] == 0
        offset = 0
        for character in text:
            size = len(character.encode('utf-8'))
            if size > 1:
                position = c.c_int(offset+1)
                assert library.utf8_nextCharSafeBody(data, c.byref(position), len(data), data[offset], -1) == ord(character)
                assert position.value == offset+size
                assert library.utf8_back1SafeBody(data, 0, offset+size-1) == offset
            offset += size
    for data in (b'\xc0\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xe2', b'\xe2\x82', b'\xe2X', b'\xff'):
        position = c.c_int(1)
        assert library.utf8_nextCharSafeBody(data, c.byref(position), len(data), data[0], -1) == -1
        assert 1 <= position.value <= len(data)
    unchanged = (unit * 3)(ord('x'), 0x315, 0x300)
    result = (unit * 4)()
    status = c.c_int()
    assert library.unorm_normalize(unchanged, 3, 1, 0, result, 4, c.byref(status)) == 3
    assert bytes(result)[:6] == bytes(unchanged)
    assert library.u_charType(ord('A')) == 1
    assert library.u_charType(0x301) == 6
    assert library.u_getIntPropertyValue(0x4e00, 0x1004) == 5
    assert library.u_charMirror(ord('(')) == ord(')')
    assert library.u_isMirrored(ord('(')) == 1
    random.seed(453)
    vectors = ['', 'abc', 'e\u0301', '\u212b', '\u1100\u1161\u11a8', '\uac01',
               'x\u0315\u0300\u05ae\u0301', '\ufb03', '\U0001d15e', '\u1f82']
    alphabet = 'aAeEoO\u0300\u0301\u0308\u0315\u0327\u0344\u212b\u1100\u1161\u11a8'
    vectors += [''.join(random.choice(alphabet) for _ in range(20)) for _ in range(500)]
    for text in vectors:
        encoded = text.encode('utf-16-le')
        source = (unit * max(1, len(encoded)//2))()
        if encoded:
            c.memmove(source, encoded, len(encoded))
        for mode, form in ((2, 'NFD'), (3, 'NFKD'), (4, 'NFC'), (5, 'NFKC')):
            expected = unicodedata.normalize(form, text).encode('utf-16-le')
            status = c.c_int()
            needed = library.unorm_normalize(source, len(encoded)//2, mode, 0, None, 0, c.byref(status))
            assert needed == len(expected)//2, (form, repr(text), needed, len(expected)//2)
            assert status.value == (15 if needed else -124)
            result = (unit * (needed+1))()
            status.value = 0
            count = library.unorm_normalize(source, len(encoded)//2, mode, 0, result, needed+1, c.byref(status))
            assert status.value <= 0 and count == needed
            assert bytes(result)[:needed*2] == expected, (form, repr(text))
            assert result[needed] == 0
            status.value = 0
            assert bool(library.unorm_isNormalized(source, len(encoded)//2, mode, c.byref(status))) == (expected == encoded)
    print('UTF-8 boundaries, buffer canaries, Unicode properties, and %d normalization cases passed' % (len(vectors)*4))


if __name__ == '__main__':
    check(sys.argv[1])
