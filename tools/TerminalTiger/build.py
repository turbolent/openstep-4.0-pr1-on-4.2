"""Build an OPENSTEP compatibility bundle from a supplied Tiger Terminal.app.

Run as python tools/build.py terminal-tiger. No Apple application is downloaded.
"""
import argparse
import hashlib
import io
import json
import plistlib
import re
import shutil
import shlex
import struct
import tarfile
from pathlib import Path

from .prepare import prepare, SOURCE_SHA256
from tools.common.patch_macho import add_app_icon

SOURCES = ('graphics.m', 'atsui.m', 'core.m', 'struct-return.m',
           'accessibility.m', 'abi.m', 'unicode.m', 'services.m', 'network.m', 'scripting.m', 'appkit.m')
ABI_NAMES = {'fprintf','fputc','fflush','popen','pclose','stat','fstat','statfs',
             'getpwuid','getpwnam','setenv','tcgetattr','tcsetattr','ioctl',
             'forkpty','close','NSUnionRect','NSOffsetRect','usleep'}
RUNTIME = '''
void _NSAddHandler2(NSHandler *h) { _NSAddHandler(h); }
void _NSRemoveHandler2(NSHandler *h) { _NSRemoveHandler(h); }
id _NSExceptionObjectFromHandler2(NSHandler *h) { return _NSExceptionObjectFromHandler(h); }
void __keymgr_dwarf2_register_sections(void) {}
'''


def compatibility_source():
    directory = Path(__file__).parent
    sources = [(directory/name).read_text() for name in SOURCES]
    implemented = {'___CFConstantStringClassReference','__NSAddHandler2',
                   '__NSRemoveHandler2','__NSExceptionObjectFromHandler2',
                   '___keymgr_dwarf2_register_sections','_objc_msgSend_stret',
                   '___sF','__DefaultRuneLocale','___error','_modff','_reallocf',
                   '_pututxline','_kCFAllocatorDefault','_kCFRunLoopCommonModes',
                   '_kScrollWheelMultiplier','_NSURLPboardType'}
    implemented.update('_'+name for name in ABI_NAMES)
    for source in sources:
        implemented.update('_'+name for name in re.findall(r'^(?:void \*|void|id|int|unsigned|double|TigerFixed)\s*(\w+)\(',source,re.M))
        implemented.update('.objc_class_name_'+name for name in re.findall(r'^@interface (\w+)\s*:',source,re.M))
        implemented.update('_'+name for name in re.findall(r'^NSString \*(NSAccessibility\w+)\s*=',source,re.M))
    unresolved = sorted(set((directory/'imports.txt').read_text().splitlines())-implemented)
    if unresolved:
        raise ValueError('Missing compatibility interfaces: '+', '.join(unresolved))
    return '#import <AppKit/AppKit.h>\n#include <stdio.h>\n#include <stdlib.h>\n'+RUNTIME+'\n'.join(sources), unresolved


def openstep_plist(value):
    """Encode metadata for OPENSTEP's pre-XML property-list reader."""
    if isinstance(value,dict):
        return '{ '+''.join(openstep_plist(str(k))+' = '+openstep_plist(v)+'; ' for k,v in value.items())+'}'
    if isinstance(value,list):return '('+', '.join(openstep_plist(v) for v in value)+')'
    if isinstance(value,bool):value='YES' if value else 'NO'
    return json.dumps(str(value),ensure_ascii=True).replace('\\u','\\U')


def native_icon(pixels):
    """Encode premultiplied RGBA with the associated-alpha TIFF tag."""
    from PIL import Image
    pixels = pixels.convert('RGBA')
    pixels.thumbnail((48, 48), Image.Resampling.LANCZOS)
    premultiplied = pixels.convert('RGBa')
    storage = Image.frombytes('RGBA', pixels.size, premultiplied.tobytes())
    buffer = io.BytesIO()
    storage.save(buffer, format='TIFF', compression='raw')
    data = bytearray(buffer.getvalue())
    endian = '<' if data[:2] == b'II' else '>'
    directory = struct.unpack_from(endian + 'I', data, 4)[0]
    count = struct.unpack_from(endian + 'H', data, directory)[0]
    for index in range(count):
        offset = directory + 2 + index * 12
        tag, kind, number = struct.unpack_from(endian + 'HHI', data, offset)
        if tag == 338:
            assert kind == 3 and number == 1
            struct.pack_into(endian + 'H', data, offset + 8, 1)
            return bytes(data)
    raise ValueError('TIFF encoder did not emit an alpha-sample tag')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,required=True,help='Verified universal Tiger Terminal.app')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--runtime-directory',required=True,help='Absolute directory on OPENSTEP containing TigerCompat.dylib')
    parser.add_argument('--experimental',action='store_true',help='Retained for compatibility with earlier build commands')
    args=parser.parse_args()
    contents=args.source/'Contents'
    executable=prepare((contents/'MacOS/Terminal').read_bytes(),args.runtime_directory)
    source, unresolved=compatibility_source()
    from .nibgen import generate
    args.output.mkdir(parents=True,exist_ok=True)
    generated=args.output/'generated-nibs.m'
    generate(contents/'Resources',generated)
    (args.output/'compat.m').write_text(source+'\n'+generated.read_text(),encoding='ascii',newline='\n')
    directory=Path(__file__).parent
    unit='#import <AppKit/AppKit.h>\n#import <objc/objc-class.h>\n'
    unit+='\n'.join((directory/name).read_text() for name in ('core.m','struct-return.m','abi.m','unicode.m','network.m','scripting.m','tests/native-unit.m'))
    (args.output/'native-unit.m').write_text(unit,encoding='ascii',newline='\n')
    bounds_test='\n'.join((directory/name).read_text() for name in
                          ('graphics.m','atsui.m','tests/atsui-bounds.m'))
    (args.output/'atsui-bounds.m').write_text(bounds_test,encoding='ascii',newline='\n')
    shell_test=(directory/'abi.m').read_text()+'\n'+(directory/'tests/shell-pty.m').read_text()
    (args.output/'shell-pty.m').write_text(shell_test,encoding='ascii',newline='\n')
    app=args.output/'TerminalTiger.app'
    app.mkdir(exist_ok=True)
    shutil.copytree(contents/'Resources',app/'Resources',dirs_exist_ok=True)
    info=plistlib.loads((contents/'Info.plist').read_bytes())
    info.update(NSExecutable='TerminalTiger',NSMainNibFile='Terminal',NSPrincipalClass='TerminalApp',NSPortName='TerminalTiger',NSIcon='icon',CFBundleExecutable='TerminalTiger',CFBundleIdentifier='local.TerminalTiger',CFBundleIconFile='icon.tiff')
    info['NSTypes']=[{'NSName':doc['CFBundleTypeName'],'NSUnixExtensions':doc['CFBundleTypeExtensions'],'NSIcon':Path(doc['CFBundleTypeIconFile']).stem,'NSRole':'Editor'} for doc in info.get('CFBundleDocumentTypes',[])]
    from PIL import Image
    for icon in ('icon','term_icon','command_icon'):
        with Image.open(contents/'Resources'/(icon+'.icns')) as pixels:
            (app/'Resources'/(icon+'.tiff')).write_bytes(native_icon(pixels))
    for name in ('Info.plist','Info-nextstep.plist'):
        (app/'Resources'/name).write_text(openstep_plist(info)+'\n',encoding='ascii')
    # Workspace discovers native apps from the legacy Mach-O __ICON section.
    executable=add_app_icon(executable,'TerminalTiger',(app/'Resources/icon.tiff').read_bytes())
    (app/'TerminalTiger').write_bytes(executable)
    shutil.copyfile(directory/'README.md',args.output/'README.md')
    shutil.copyfile(directory/'tests/terminal-fixture.c',args.output/'terminal-fixture.c')
    script='''#!/bin/sh
set -e
cd %s
cc -fno-common -dynamiclib -undefined suppress \\
  -Wl,-install_name,%s/TigerCompat.dylib,-compatibility_version,1.0,-current_version,1.0 \\
  -o TigerCompat.dylib.new compat.m -framework AppKit -framework Foundation
mv TigerCompat.dylib.new TigerCompat.dylib
chmod +x TerminalTiger.app/TerminalTiger
'''
    directory=shlex.quote(args.runtime_directory.rstrip('/'))
    (args.output/'build-on-openstep.sh').write_text(script % (directory,directory),encoding='ascii',newline='\n')
    manifest={'sourceIntelSHA256':SOURCE_SHA256,'preparedSHA256':hashlib.sha256(executable).hexdigest(),
              'runtimeDirectory':args.runtime_directory,'status':'prepared-native-compilation-required',
              'unimplementedImports':unresolved,'convertedNibs':['Terminal','Term','Find','Preferences','CommandPanel','InspectorX','AccessoryViews','ServiceBrowser'],
              'limitations':['Native font coverage and text shaping; no Quartz antialiasing or transparency','No secure keyboard input service','No external AppleScript transport','Bonjour supports local IPv4 discovery; resolved .local names require a resolver in the launched client','No Tiger utmpx login accounting']}
    (args.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    def archive_permissions(info):
        info.mode=0o755 if info.isdir() or info.name in ('TerminalTiger.app/TerminalTiger','build-on-openstep.sh') else 0o644
        info.mtime=int(info.mtime)
        return info
    with tarfile.open(args.output/'TerminalTiger-source-bundle.tar.gz','w:gz',format=tarfile.GNU_FORMAT) as archive:
        for name in ('TerminalTiger.app','compat.m','build-on-openstep.sh','manifest.json','native-unit.m','atsui-bounds.m','shell-pty.m','terminal-fixture.c','README.md'):
            archive.add(args.output/name,arcname=name,filter=archive_permissions)
    print('Prepared compatibility bundle:',args.output)
    print('Unimplemented imports:',len(unresolved))


if __name__=='__main__':
    main()
