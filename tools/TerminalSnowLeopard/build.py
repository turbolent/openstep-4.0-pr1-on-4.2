"""Prepare a native compatibility bundle from a supplied Snow Leopard Terminal.app."""
import argparse
import hashlib
import json
import plistlib
import shutil
import shlex
import struct
import tarfile
from pathlib import Path

from tools.TerminalTiger.build import compatibility_source, native_icon, openstep_plist
from tools.common.macho import MachO
from tools.common.patch_macho import add_app_icon, intel_slice
from .prepare import prepare, SOURCE_SHA256, import_name
from .nibgen import generate
from .pcre import prepare_pcre

SOURCES = ('runtime.m', 'abi.m', 'foundation.m', 'blocks.m', 'scripting.m', 'format.m', 'dispatch.m', 'bindings.m', 'predicate.m', 'controllers.m', 'undo.m', 'toolbar.m', 'plist.m', 'core.m', 'unicode-data.inc', 'unicode.c', 'wordbreak-data.inc', 'wordbreak.c', 'tokenizer.m', 'regex.c', 'unicode-foundation.m', 'coretext.m', 'bezier.m', 'graphics.m', 'tracking.m', 'animation.m', 'audio.m', 'colorsync.c', 'platform.m', 'appkit.m')


def struct_wrappers(contents):
    data = intel_slice(contents)
    image = MachO(data)
    def words(address, count):
        return struct.unpack_from('<' + 'I' * count, data, image.offset(address))
    def string(address):
        position = image.offset(address)
        return data[position:data.index(0, position)].decode('ascii')
    result = ['void SnowInitializeStructReturns(void) {']
    def methods(cls, address, meta=False):
        if not address:
            return
        for i in range(words(address+4, 1)[0]):
            name, types, implementation = words(address+8+i*12, 3)
            expression = 'NSClassFromString(@%s)' % json.dumps(cls)
            if meta:
                expression = '*(Class *)(void *)' + expression
            result.append('SnowWrapMethod(%s,sel_getUid(%s));' % (expression, json.dumps(string(name))))
    for section in image.sections:
        name = section.name.rstrip(b'\0')
        if name == b'__class':
            for address in range(section.address, section.address+section.size, 48):
                fields = words(address, 12)
                methods(string(fields[2]), fields[7])
                methods(string(fields[2]), words(fields[0], 8)[7], True)
        elif name == b'__category':
            for address in range(section.address, section.address+section.size, 28):
                fields = words(address, 7)
                methods(string(fields[1]), fields[2])
                methods(string(fields[1]), fields[3], True)
    # Redirect only the executable's sends; preserve native collection/menu rules.
    # Explicit-zone sends stay native: the settings cell's copyWithZone:
    # override sends that selector to super before copying its child cells.
    # Aliasing it would dispatch through NSObject's helper back to the override.
    copies = {'copy': 'snowCopy', 'mutableCopy': 'snowMutableCopy',
              'indexOfItem:': 'snowIndexOfItem:',
              'indexOfItemWithTarget:andAction:': 'snowIndexOfItemWithTarget:andAction:'}
    for section in image.sections:
        if section.name.rstrip(b'\0') == b'__message_refs':
            for address in range(section.address, section.address + section.size, 4):
                name = string(words(address, 1)[0])
                if name in copies:
                    result.append('*(SEL *)0x%x=sel_getUid(%s);' %
                                  (address, json.dumps(copies[name])))
    result.append('}')
    return '\n'.join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runtime-directory', required=True)
    parser.add_argument('--pcre-archive', type=Path, help='Optional offline PCRE 8.45 source archive')
    args = parser.parse_args()
    contents = args.source/'Contents'
    original = (contents/'MacOS/Terminal').read_bytes()
    executable = prepare(original, args.runtime_directory)
    args.output.mkdir(parents=True, exist_ok=True)
    prepare_pcre(args.output, args.pcre_archive)
    source, _ = compatibility_source()
    directory = Path(__file__).parent
    source += '\n' + '\n'.join((directory/name).read_text() for name in SOURCES)
    source += '\n' + struct_wrappers(original)
    generated = args.output/'generated-nibs.m'
    generate(contents/'Resources', generated)
    (args.output/'compat.m').write_text(source+'\n'+generated.read_text(), encoding='ascii', newline='\n')
    app = args.output/'TerminalSnowLeopard.app'
    app.mkdir(exist_ok=True)
    shutil.copytree(contents/'Resources', app/'Resources', dirs_exist_ok=True)
    info = plistlib.loads((contents/'Info.plist').read_bytes())
    info.update(NSExecutable='TerminalSnowLeopard', NSMainNibFile='MainMenu', NSPrincipalClass='TTApplication', NSPortName='TerminalSnowLeopard', NSIcon='icon', CFBundleExecutable='TerminalSnowLeopard', CFBundleIdentifier='local.TerminalSnowLeopard', CFBundleIconFile='icon.tiff')
    from PIL import Image
    with Image.open(contents/'Resources/Terminal.icns') as pixels:
        (app/'Resources/icon.tiff').write_bytes(native_icon(pixels))
    for name in ('Info.plist', 'Info-nextstep.plist'):
        (app/'Resources'/name).write_text(openstep_plist(info)+'\n', encoding='ascii')
    executable = add_app_icon(executable, 'TerminalSnowLeopard', (app/'Resources/icon.tiff').read_bytes())
    (app/'TerminalSnowLeopard').write_bytes(executable)
    remote = shlex.quote(args.runtime_directory.rstrip('/'))
    script = '''#!/bin/sh
set -e
cd %s
free_kb=`df . | awk 'NR == 2 { print $4 }'`
if [ -z "$free_kb" ] || [ "$free_kb" -lt 131072 ]; then
  echo "At least 128 MiB of free disk space is required to build Terminal."
  exit 1
fi
sh build-regex.sh
cc -fno-common -dynamiclib -undefined suppress \\
  -Wl,-install_name,%s/SnowCompat.dylib,-compatibility_version,1.0,-current_version,1.0 \\
  -o SnowCompat.dylib.new compat.m pcre16/libSnowRegex.a -framework AppKit -framework Foundation
mv SnowCompat.dylib.new SnowCompat.dylib
chmod +x TerminalSnowLeopard.app/TerminalSnowLeopard
''' % (remote, remote)
    (args.output/'build-on-openstep.sh').write_text(script, encoding='ascii', newline='\n')
    shutil.copyfile(directory/'UNICODE-LICENSE.txt', args.output/'UNICODE-LICENSE.txt')
    manifest = {'sourceIntelSHA256': SOURCE_SHA256, 'preparedSHA256': hashlib.sha256(executable).hexdigest(), 'runtimeDirectory': args.runtime_directory, 'status': 'prepared-native-compilation-required'}
    (args.output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    def permissions(item):
        item.mode = 0o755 if item.isdir() or item.name in ('TerminalSnowLeopard.app/TerminalSnowLeopard', 'build-on-openstep.sh') else 0o644
        return item
    with tarfile.open(args.output/'TerminalSnowLeopard-source-bundle.tar.gz','w:gz',format=tarfile.GNU_FORMAT) as archive:
        for name in ('TerminalSnowLeopard.app','compat.m','build-on-openstep.sh','build-regex.sh','pcre16','manifest.json','UNICODE-LICENSE.txt'):
            archive.add(args.output/name, arcname=name, filter=permissions)
    print('Prepared Snow Leopard compatibility bundle:', args.output)


if __name__ == '__main__':
    main()
