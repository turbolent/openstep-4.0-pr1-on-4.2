"""Prepare the pinned C89 regex dependency for the native OPENSTEP compiler."""
import hashlib
import re
import tarfile
import urllib.request
from pathlib import Path

VERSION = '8.45'
SHA256 = '4dae6fdcd2bb0bb6c37b5f97c33c2be954da743985369cddac3546e3218bffb8'
URL = f'https://downloads.sourceforge.net/project/pcre/pcre/{VERSION}/pcre-{VERSION}.tar.bz2'
MODULES = ('byte_order', 'chartables', 'compile', 'config', 'dfa_exec', 'exec',
           'fullinfo', 'get', 'globals', 'jit_compile', 'maketables', 'newline',
           'ord2utf16', 'refcount', 'string_utils', 'study', 'tables', 'ucd',
           'utf16_utils', 'valid_utf16', 'version', 'xclass')


def prepare_pcre(output, archive=None):
    output = Path(output)
    archive = Path(archive) if archive else output / f'pcre-{VERSION}.tar.bz2'
    if not archive.exists():
        request = urllib.request.Request(URL, headers={'User-Agent': 'TerminalSnowLeopard-builder'})
        with urllib.request.urlopen(request, timeout=60) as response:
            contents = response.read(8 * 1024 * 1024)
        if hashlib.sha256(contents).hexdigest() != SHA256:
            raise ValueError('PCRE source archive checksum mismatch')
        archive.write_bytes(contents)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise ValueError('Expected the unmodified PCRE 8.45 source archive')
    target = output / 'pcre16'
    target.mkdir(exist_ok=True)
    with tarfile.open(archive) as source:
        def read(name):
            return source.extractfile(f'pcre-{VERSION}/{name}').read()

        pending = {f'pcre16_{name}.c' for name in MODULES}
        pending.update(('pcre_internal.h', 'ucp.h', 'LICENCE'))
        written = set()
        while pending:
            name = pending.pop()
            if name in written:
                continue
            if Path(name).name != name:
                raise ValueError('Unexpected PCRE include path')
            contents = read(name)
            (target / name).write_bytes(contents)
            written.add(name)
            for include in re.findall(rb'^#include "(pcre[^"/]+\.[ch]|ucp\.h)"', contents, re.M):
                include = include.decode('ascii')
                if include not in ('pcre.h', 'pcre_chartables.c'):
                    pending.add(include)
        (target / 'pcre.h').write_bytes(read('pcre.h.generic'))
        (target / 'pcre_chartables.c').write_bytes(read('pcre_chartables.c.dist'))
        config = read('config.h.generic').decode('ascii')
    for flag in ('SUPPORT_PCRE16', 'SUPPORT_UTF', 'SUPPORT_UCP', 'NO_RECURSE',
                 'HAVE_MEMMOVE', 'HAVE_STDLIB_H', 'HAVE_STRING_H'):
        config = config.replace(f'/* #undef {flag} */', f'#define {flag} 1')
    config = config.replace('#define MATCH_LIMIT 10000000', '#define MATCH_LIMIT 1000000')
    config = config.replace('#define MATCH_LIMIT_RECURSION MATCH_LIMIT', '#define MATCH_LIMIT_RECURSION 10000')
    (target / 'config.h').write_text(config, encoding='ascii', newline='\n')
    script = '#!/bin/sh\nset -e\ncd pcre16\n'
    for name in MODULES:
        script += f'cc -DHAVE_CONFIG_H -I. -fno-common -c pcre16_{name}.c -o {name}.o\n'
    script += 'ar cr libSnowRegex.a ' + ' '.join(f'{name}.o' for name in MODULES) + '\n'
    script += 'ranlib libSnowRegex.a\n'
    (output / 'build-regex.sh').write_text(script, encoding='ascii', newline='\n')
