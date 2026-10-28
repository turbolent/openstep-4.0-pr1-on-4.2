"""Generate Unicode 5.1 word-boundary properties (UAX #29 revision 13)."""
import argparse
import hashlib
from pathlib import Path

PROPERTIES = 'Other CR LF Newline Extend Format Katakana ALetter MidNumLet MidLetter MidNum Numeric ExtendNumLet'.split()


def generate(source, output):
    data = source.read_bytes()
    ranges = []
    for line in data.decode('utf-8').splitlines():
        value = line.split('#', 1)[0].strip()
        if not value:
            continue
        bounds, prop = (part.strip() for part in value.split(';'))
        bounds = [int(part, 16) for part in bounds.split('..')]
        ranges.append((bounds[0], bounds[-1], PROPERTIES.index(prop)))
    result = ['/* Unicode 5.1 WordBreakProperty.txt. See UNICODE-LICENSE.txt.',
              ' * SHA-256 ' + hashlib.sha256(data).hexdigest() + ' */',
              'enum { ' + ', '.join('SNWB_' + prop for prop in PROPERTIES) + ' };',
              'static const struct { unsigned first,last; unsigned char property; } snowWordProperties[] = {']
    result += ['{0x%x,0x%x,%d},' % row for row in sorted(ranges)]
    result += ['};', '']
    output.write_text('\n'.join(result), encoding='ascii', newline='\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    generate(args.source, args.output)
