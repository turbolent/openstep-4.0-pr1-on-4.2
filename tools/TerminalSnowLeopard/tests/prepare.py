"""Generate standalone native tests without an Apple application or runtime globals."""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent.parent
    headers = '''#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
'''
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'test-drawing-all.m').write_text(
        headers + '#define SNOW_DRAWING_TEST_COMBINED\n'
        'static void snowBadPlist(void) { '
        '[NSException raise:NSInvalidArgumentException format:@"Invalid text range"]; }\n' +
        (directory.parent / 'TerminalTiger/graphics.m').read_text() +
        (directory / 'coretext.m').read_text() + (directory / 'tests/drawing.m').read_text(),
        encoding='ascii', newline='\n')
    (args.output / 'test-audio-all.m').write_text(
        headers + '\n'.join((directory / name).read_text() for name in
                             ('tests/audio-url.m', 'audio.m', 'tests/audio.m')),
        encoding='ascii', newline='\n')
    (args.output / 'test-services-all.m').write_text(
        headers + '#include <limits.h>\n#include <math.h>\n#include <mach/mach.h>\n'
        'static NSRecursiveLock *snowRuntimeLock;\n' +
        '\n'.join((directory / name).read_text() for name in
                  ('blocks.m', 'wordbreak-data.inc', 'wordbreak.c', 'tokenizer.m',
                   'colorsync.c', 'platform.m', 'tests/services.m')),
        encoding='ascii', newline='\n')
    (args.output / 'test-regex.c').write_text(
        '#include <stdio.h>\n#include <stdlib.h>\n#include <string.h>\n#include <limits.h>\n' +
        (directory / 'regex.c').read_text() + (directory / 'tests/regex.c').read_text(),
        encoding='ascii', newline='\n')
    names = ('foundation.m', 'format.m', 'bindings.m', 'tests/foundation.m')
    (args.output / 'test-foundation-all.m').write_text(
        headers + '\n'.join((directory / name).read_text() for name in names),
        encoding='ascii', newline='\n')
    (args.output / 'test-native-controls-all.m').write_text(
        headers + '\n'.join((directory / name).read_text() for name in
                            ('foundation.m', 'format.m', 'bindings.m', 'tests/native-controls.m')),
        encoding='ascii', newline='\n')
    (args.output / 'test-dispatch-all.m').write_text(
        headers + '\n'.join((directory / name).read_text() for name in
                            ('foundation.m', 'format.m', 'bindings.m', 'dispatch.m')) +
        (directory / 'tests/dispatch.m').read_text(), encoding='ascii', newline='\n')
    runtime = (directory / 'runtime.m').read_text()
    assembly = runtime[runtime.index('asm('):runtime.index('void SnowWrapMethod')]
    (args.output / 'test-abi.c').write_text(
        assembly + (directory / 'tests/abi.c').read_text(), encoding='ascii', newline='\n')
    (args.output / 'test-editors-all.m').write_text(
        headers + 'static BOOL TigerLoadNib(NSString *name,id owner) { return NO; }\n' +
        '\n'.join((directory / name).read_text() for name in
                  ('foundation.m', 'format.m', 'bindings.m', 'predicate.m',
                   'controllers.m', 'undo.m', 'plist.m', 'tests/editors.m')),
        encoding='ascii', newline='\n')


if __name__ == '__main__':
    main()
