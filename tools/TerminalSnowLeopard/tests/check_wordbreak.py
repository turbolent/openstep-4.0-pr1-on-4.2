"""Check a compiled word-boundary library against Unicode's WordBreakTest.txt."""
import ctypes
import sys
from pathlib import Path


def check(library, vectors):
    boundary = ctypes.CDLL(str(library)).SnowWordBoundary
    boundary.argtypes = [ctypes.POINTER(ctypes.c_ushort), ctypes.c_uint, ctypes.c_uint]
    count = 0
    for number, line in enumerate(vectors.read_text(encoding='utf-8').splitlines(), 1):
        fields = line.split('#', 1)[0].split()
        if not fields:
            continue
        encoded = ''.join(chr(int(code, 16)) for code in fields[1::2]).encode('utf-16-le')
        units = (ctypes.c_ushort * (len(encoded)//2)).from_buffer_copy(encoded)
        expected, offset = set(), 0
        for i in range(0, len(fields), 2):
            if fields[i] == '\u00f7':
                expected.add(offset)
            if i+1 < len(fields):
                offset += 2 if int(fields[i+1], 16) > 0xffff else 1
        actual = {i for i in range(len(units)+1) if boundary(units, len(units), i)}
        assert actual == expected, (number, fields, actual, expected)
        count += 1
    print(f'PASS: {count} Unicode word-boundary vectors')


if __name__ == '__main__':
    check(Path(sys.argv[1]), Path(sys.argv[2]))
