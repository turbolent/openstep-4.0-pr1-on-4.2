"""Build a private Rhapsody DR2 framework runtime for OPENSTEP 4.2."""

import argparse
import hashlib
import shlex
import shutil
import struct
import tempfile
from pathlib import Path, PurePosixPath

from . import macho, require
from .build_dr2 import package
from .dr2 import install_path, load_commands, patch_image
from .patch_macho import dylib_command, intel_slice, rewrite_libraries

COMPATIBILITY_LIBRARY = "ABI.dylib"
LINKEDIT_VM_SIZE = 28
LINKEDIT_FILE_SIZE = 36
SEGMENT_NAME_START = macho.LOAD_COMMAND.size
SEGMENT_NAME_END = SEGMENT_NAME_START + 16
PAGE_SIZE = 4096
CONSTANT_STRING_DATA = struct.Struct("<II")
FRAMEWORK_HASHES = {
    "Foundation": "215935dfab3c083ab97e24f6b74b76c4ae668783892510f02d71ad9bfde5192b",
    "AppKit": "c046ad96712b820654046927b83d3bb56d5daccd51fe06105f9574012005c00e",
    "SoundKit": "31b85ffd586f7ffb844bea7b5f1e6774fe1d48d466a4521f856bb047e61b710b",
    "AppSupport": "ff763cffaaa0a38d8cacc6cc0ad24c942a82393cc95d1af4e5a3cca02428095c",
    "Message": "fab91dc2ad510b055c4722e938b0ab728c764b1e35f6b12f7e92af83e5ac305a",
    "MailViewer": "d17db3fe9ef693b0c7ce6f03d3288cce4ca291bcc6bf9962ea3be23b405b8213",
    "HTML": "0ee4566910c674608b81e78fa1e078f0008fd3fc8d8c28d9ee92aa920e484cb3",
    "ProjectBuilder": "9ec0e093716311440b62fcf9f877f1caa68bf32f87dc0afe313ddb49273b6db7",
    "PBDevKit": "0ab367532953a0b47777795fd68c2e493ca79027ce61002aa7b1094b521aee3c",
    "PBRuntime": "c860735a5b68f2f3d0b754ab8fe0c68a9d39ae29bbd8f852a0bdc0da4f79f5b1",
}
PRIVATE_FRAMEWORKS = {"AppSupport", "MailViewer", "HTML", "PBDevKit", "PBRuntime"}
FRAMEWORK_VERSIONS = {
    "AppKit": "C",
    "Foundation": "C",
    "HTML": "A",
    "ProjectBuilder": "A",
    "PBDevKit": "C",
    "PBRuntime": "A",
}
APP_SUFFIX = "DR2Runtime"
APP_LIBRARIES = {
    "Viewer": "ViewerRuntime.dylib",
    "ProjectBuilder": "ProjectBuilderRuntime.dylib",
}
APP_HASHES = {
    "Stickies": "5584032789ee99c7d46ae27e1c53de1d226bcc5ab42355444ca3607a82a8251e",
    "Viewer": "9400d39d055c6841af250f50b64193ea3d24629b712b88194da974a5b3b34790",
    "MailViewer": "ee3dc00e5d408484ffb7879449d3d2d554f1546f4a22e1ef99f24a03a8edcd90",
    "ProjectBuilder": "b6bf4b583373abefb54de1f451cb5cc27854ebf8aaa40513e2199ff899f7099f",
}
VIEWER_PRIVATE_NAMES = {
    b"apps5_1.ppl": b"appsDRT.ppl",
    b"suffixes5_1.i386.wmd": b"suffixesDRT.i386.wmd",
    b"Miniapp_boot_port": b"ViewerRT_toolport",
    b"File Viewer address server": b"DR2 Runtime address server",
}
TOOL_HASHES = {
    "System/Library/CoreServices/pbs": "ddf5c0816cbd1627c6af24e3193649ef025edec87e93e18f0eaff1f29e97bc77",
    "usr/bin/fcache": "e1a5d83124d256ba2471ba5d5a5abfbb949c69d2274a5853801501facc09c135",
}
WRAPPED_FUNCTIONS = {
    "fopen",
    "fdopen",
    "fclose",
    "fread",
    "fwrite",
    "fprintf",
    "fputc",
    "fputs",
    "setbuf",
    "stat",
    "fstat",
    "lstat",
    "connect",
    "readdir",
    "statfs",
    "fflush",
    "fgets",
    "getpwuid",
    "getpwnam",
    "getpwent",
    "getgrgid",
    "getgrnam",
    "getgrent",
    "getdirentries",
    "getrlimit",
    "setrlimit",
    "lseek",
    "ftruncate",
    "truncate",
    "fseek",
    "ftell",
    "setvbuf",
}
RESOURCE_TOOLS = {"pbs", "make_services", "cacheAFMData"}
ORIGINAL_PBS_NAMES = (b"NeXT 4.0 Pasteboard Server", b"NeXT Pasteboard Server")
ORIGINAL_NOTIFICATION_NAME = b"Apple DNC Server (Local Host)"
PBS_DISCONNECT_FILES = 0x5CF4
X86_RETURN = b"\xc3"
X86_PUSH_FRAME_POINTER = b"\x55"
STICKIES_DATABASE = b".StickiesDatabase"
RUNTIME_STICKIES_DATABASE = b".StickiesDR2Stack"
PROJECT_BUILDER_DEBUGGER = b'Debugger = "/usr/bin/gdb"'
NATIVE_DEBUGGER = b'Debugger = "/bin/gdb"'


def update_linkedit_size(data, image):
    segment = next(s for s in image.segments if s.name.rstrip(b"\0") == b"__LINKEDIT")
    for kind, offset, command in load_commands(data):
        if (
            kind == macho.LC_SEGMENT
            and command[SEGMENT_NAME_START:SEGMENT_NAME_END].rstrip(b"\0")
            == b"__LINKEDIT"
        ):
            length = len(data) - segment.fileoff
            macho.UINT32.pack_into(data, offset + LINKEDIT_FILE_SIZE, length)
            macho.UINT32.pack_into(
                data, offset + LINKEDIT_VM_SIZE, macho.align_up(length, PAGE_SIZE)
            )
            return


def framework_binary(root, name):
    directory = "PrivateFrameworks" if name in PRIVATE_FRAMEWORKS else "Frameworks"
    version = FRAMEWORK_VERSIONS.get(name, "B")
    return (
        root
        / "System/Library"
        / directory
        / (name + ".framework")
        / "Versions"
        / version
        / name
    )


def dependencies(data):
    for kind, _, command in load_commands(intel_slice(data)):
        if kind != macho.LC_LOAD_DYLIB:
            continue
        _, _, offset, *_ = macho.DYLIB_COMMAND.unpack_from(command)
        yield command[offset:].split(b"\0")[0].decode("ascii").rsplit("/", 1)[-1]


def required_frameworks(root, apps):
    required = {"AppKit", "Foundation"}
    pending = list(required)
    for app in apps:
        for path in app.rglob("*"):
            if path.is_file():
                data = path.read_bytes()
                if data.startswith((macho.MACH_MAGIC_I386, macho.FAT_MAGIC)):
                    pending.extend(dependencies(data))
    inspected = {"System"}
    while pending:
        name = pending.pop()
        if name in inspected:
            continue
        require(name in FRAMEWORK_HASHES, "Unsupported DR2 framework: " + name)
        inspected.add(name)
        required.add(name)
        pending.extend(dependencies(framework_binary(root, name).read_bytes()))
    return sorted(required)


def private_names(destination):
    digest = hashlib.sha256(destination.encode("ascii")).hexdigest()
    templates = (b"DR2 Pasteboard Server", b"D Pasteboard Server")
    return (
        b"DR2"
        + digest[: len(ORIGINAL_PBS_NAMES[0]) - len(templates[0])].encode("ascii")
        + b" Pasteboard Server",
        b"D"
        + digest[: len(ORIGINAL_PBS_NAMES[1]) - len(templates[1])].encode("ascii")
        + b" Pasteboard Server",
    )


def notification_name(destination):
    digest = hashlib.sha256(destination.encode("ascii")).hexdigest()
    template = b"D DNC Server (Local Host)"
    length = len(ORIGINAL_NOTIFICATION_NAME) - len(template)
    return b"D" + digest[:length].encode("ascii") + b" DNC Server (Local Host)"


def patch_framework_paths(data, replacements):
    """Redirect constant strings without overwriting shared C string suffixes."""
    image = macho.MachO(data)
    segment = next(s for s in image.segments if s.name.rstrip(b"\0") == b"__LINKEDIT")
    result = bytearray(data)
    for old, new in replacements.items():
        for section in image.sections:
            if section.name.rstrip(b"\0") != b"__cstring":
                continue
            cursor = section.fileoff
            end = cursor + section.size
            while True:
                cursor = data.find(old + b"\0", cursor, end)
                if cursor < 0:
                    break
                address = section.address + cursor - section.fileoff
                pattern = CONSTANT_STRING_DATA.pack(address, len(old))
                locations = []
                for constants in image.sections:
                    if constants.segment.rstrip(b"\0") not in (b"__DATA", b"__OBJC"):
                        continue
                    start = constants.fileoff
                    limit = start + constants.size
                    while True:
                        start = data.find(pattern, start, limit)
                        if start < 0:
                            break
                        locations.append(start)
                        start += CONSTANT_STRING_DATA.size
                if locations:
                    target = segment.vmaddr + len(result) - segment.fileoff
                    result.extend(new + b"\0")
                    for location in locations:
                        CONSTANT_STRING_DATA.pack_into(
                            result, location, target, len(new)
                        )
                cursor += len(old) + 1
    update_linkedit_size(result, image)
    return bytes(result)


def adapt_image(data, destination):
    data = intel_slice(data)
    libraries = {
        "System": "/NextLibrary/Frameworks/System.framework/System",
        **{
            name: destination + "/" + name + ".framework/" + name
            for name in FRAMEWORK_HASHES
        },
    }
    for kind, _, command in load_commands(data):
        if kind not in (macho.LC_LOAD_DYLIB, macho.LC_ID_DYLIB):
            continue
        _, _, offset, *_ = macho.DYLIB_COMMAND.unpack_from(command)
        path = command[offset:].split(b"\0")[0].decode("ascii")
        require(
            path.rsplit("/", 1)[-1] in libraries,
            "Unsupported runtime dependency: " + path,
        )
    result = patch_image(
        data,
        destination,
        frameworks=FRAMEWORK_HASHES,
        wrapped_functions=WRAPPED_FUNCTIONS,
        library_paths=libraries,
        compatibility_library=COMPATIBILITY_LIBRARY,
    )
    result = result.replace(ORIGINAL_NOTIFICATION_NAME, notification_name(destination))
    for old, new in VIEWER_PRIVATE_NAMES.items():
        require(
            len(old) == len(new), "Private Viewer names must preserve string lengths."
        )
        result = result.replace(old + b"\0", new + b"\0")
    return result


def copy_resources(source, target, destination):
    require(source.is_dir(), "Missing Resources directory: " + str(source))
    shutil.copytree(
        source,
        target,
        ignore=lambda directory, names: [
            name
            for name in names
            if name in RESOURCE_TOOLS or (Path(directory) / name).is_symlink()
        ],
    )
    for path in target.rglob("*"):
        if path.is_file():
            data = path.read_bytes()
            if data.startswith((macho.MACH_MAGIC_I386, macho.FAT_MAGIC)):
                path.write_bytes(adapt_image(data, destination))


def prepare_project_builder(root, output, destination):
    developer = root / "System/Developer"
    for resource in ("Makefiles/Resources", "PBBundles/PBRTAdaptors"):
        copy_resources(
            developer / resource, output / "Developer" / resource, destination
        )
    compiler = output / "Developer/Makefiles/Resources/ccSpec.plist"
    compiler.write_bytes(compiler.read_bytes().replace(b'"/usr/bin/cc"', b'"/bin/cc"'))
    copy_resources(
        root / "System/Documentation/Developer/HomePages",
        output / "Library/Documentation/Developer/HomePages",
        destination,
    )


def project_builder_defaults(data):
    require(PROJECT_BUILDER_DEBUGGER in data, "Unexpected Project Builder defaults.")
    offset = data.index(PROJECT_BUILDER_DEBUGGER)
    start = data.rfind(b"\0", 0, offset) + 1
    end = data.index(b"\0", offset)
    original = data[start:end]
    return patch_framework_paths(
        data, {original: original.replace(PROJECT_BUILDER_DEBUGGER, NATIVE_DEBUGGER)}
    )


def prepare(root, output, destination, apps):
    names = private_names(destination)
    frameworks = required_frameworks(root, apps)
    output.mkdir()
    for path, expected_hash in TOOL_HASHES.items():
        require(
            hashlib.sha256((root / path).read_bytes()).hexdigest() == expected_hash,
            "Unsupported DR2 tool: " + path,
        )
    fonts = root / "System/Library/Fonts"
    require(fonts.is_dir(), "Missing stock DR2 Fonts directory.")
    (output / "Library").mkdir()
    shutil.copytree(fonts, output / "Library/Fonts")
    for name in frameworks:
        expected_hash = FRAMEWORK_HASHES[name]
        source = framework_binary(root, name)
        data = source.read_bytes()
        require(
            hashlib.sha256(data).hexdigest() == expected_hash,
            "Unsupported DR2 " + name + " framework.",
        )
        target = output / (name + ".framework")
        target.mkdir()
        data = adapt_image(data, destination)
        replacements = {}
        for framework in frameworks:
            folder = (
                "PrivateFrameworks" if framework in PRIVATE_FRAMEWORKS else "Frameworks"
            )
            original = (
                "/System/Library/" + folder + "/" + framework + ".framework"
            ).encode("ascii")
            replacement = (destination + "/" + framework + ".framework").encode("ascii")
            replacements[original] = replacement
            replacements[original + b"/Resources"] = replacement + b"/Resources"
        if name == "PBRuntime":
            replacements[b"/usr/bin/gdb"] = b"/bin/gdb"
        data = patch_framework_paths(data, replacements)
        (target / name).write_bytes(data)
        copy_resources(source.parent / "Resources", target / "Resources", destination)
    if any(app.stem == "ProjectBuilder" for app in apps):
        prepare_project_builder(root, output, destination)
    pbs = bytearray(
        adapt_image(
            (root / "System/Library/CoreServices/pbs").read_bytes(), destination
        )
    )
    for old, new in zip(ORIGINAL_PBS_NAMES, names):
        require(len(old) == len(new) and old in pbs, "Unexpected DR2 pbs service name.")
        pbs = pbs.replace(old, new)
    image = macho.MachO(pbs)
    offset = image.offset(PBS_DISCONNECT_FILES)
    require(
        pbs[offset : offset + len(X86_PUSH_FRAME_POINTER)] == X86_PUSH_FRAME_POINTER,
        "Unexpected DR2 pbs startup code.",
    )
    # Keep service logs available to the launcher.
    pbs[offset : offset + len(X86_RETURN)] = X86_RETURN
    (output / "pbs-dr2").write_bytes(pbs)
    (output / "fcache").write_bytes(
        adapt_image((root / "usr/bin/fcache").read_bytes(), destination)
    )
    common = Path(__file__).parent
    sources = output / "Compatibility"
    sources.mkdir()
    for name in ("dr2-abi.m", "dr2-abi.h"):
        shutil.copyfile(common / name, sources / name)
    native = sources / "dr2-runtime"
    native.mkdir()
    for source in (common / "dr2-runtime").glob("*.m"):
        shutil.copyfile(source, native / source.name)
    (native / "runtime-path.h").write_text(
        '#define DR2_RUNTIME_PATH "'
        + destination.replace("\\", "\\\\").replace('"', '\\"')
        + '"\n'
        '#define DR2_PBS_NAME "' + names[0].decode("ascii") + '"\n',
        encoding="ascii",
        newline="\n",
    )
    name = "build-on-openstep.sh"
    script = (common / "dr2-runtime" / name).read_text()
    (output / name).write_text(
        script.replace("@INSTALL_PATH@", shlex.quote(destination)),
        encoding="ascii",
        newline="\n",
    )
    bundles = output / "Apps"
    for source in apps:
        stem = source.stem
        require(
            source.suffix == ".app" and stem.isascii(), "Expected a DR2 .app bundle."
        )
        binary = source / stem
        require(binary.is_file(), "Missing app executable: " + str(binary))
        if stem in APP_HASHES:
            require(
                hashlib.sha256(binary.read_bytes()).hexdigest() == APP_HASHES[stem],
                "Unsupported DR2 " + stem + " app.",
            )
        bundles.mkdir(exist_ok=True)
        app_name = stem + APP_SUFFIX
        target = bundles / (app_name + ".app")
        require(not target.exists(), "Duplicate app bundle: " + source.name)
        shutil.copytree(source, target)
        for path in target.rglob("*"):
            if not path.is_file():
                continue
            data = path.read_bytes()
            if data.startswith((macho.MACH_MAGIC_I386, macho.FAT_MAGIC)):
                path.write_bytes(adapt_image(data, destination))
        data = (target / stem).read_bytes()
        if stem == "ProjectBuilder":
            data = project_builder_defaults(data)
        if stem == "Stickies":
            require(
                STICKIES_DATABASE + b"\0" in data, "Unexpected DR2 Stickies notes path."
            )
            data = data.replace(
                STICKIES_DATABASE + b"\0", RUNTIME_STICKIES_DATABASE + b"\0"
            )
            original = target / STICKIES_DATABASE.decode("ascii")
            require(original.is_file(), "Missing stock Stickies sample notes.")
            original.rename(target / RUNTIME_STICKIES_DATABASE.decode("ascii"))
        if stem in APP_LIBRARIES:
            data = rewrite_libraries(
                data, {}, [dylib_command(destination + "/" + APP_LIBRARIES[stem])]
            )
        (target / stem).unlink()
        (target / app_name).write_bytes(data)
        resources = target / "Resources"
        info = (resources / "Info-nextstep.plist").read_bytes()
        for key in (b"NSExecutable", b"NSPortName"):
            info = info.replace(
                key + b" = " + stem.encode("ascii") + b";",
                key + b" = " + app_name.encode("ascii") + b";",
            )
        for name in ("Info.plist", "Info-nextstep.plist"):
            (resources / name).write_bytes(info)
        if stem == "MailViewer":
            for path in (
                resources / "MailViewer.defaults",
                output / "Message.framework/Resources/Message.defaults",
            ):
                defaults = path.read_bytes()
                for old, new in (
                    (b"~/Mailboxes", b"~/MailboxesDR2Runtime"),
                    (b'"/var/mail"', b'"/usr/spool/mail"'),
                    (b'"/usr/sbin/sendmail"', b'"/usr/lib/sendmail"'),
                ):
                    defaults = defaults.replace(old, new)
                path.write_bytes(defaults)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source", type=Path, required=True, help="Extracted stock DR2 system tree."
    )
    parser.add_argument(
        "--app",
        type=Path,
        action="append",
        default=[],
        help="Stock DR2 app to include; may be repeated.",
    )
    parser.add_argument(
        "--output", type=Path, required=True, help="New runtime output directory."
    )
    parser.add_argument(
        "--install-path",
        required=True,
        help="Absolute private runtime directory on OPENSTEP.",
    )
    args = parser.parse_args()
    root = args.source.resolve()
    output = args.output.absolute()
    archive = output.with_name(output.name + "-OPENSTEP42.tar.gz")
    apps = [app.resolve() for app in args.app]
    destination = install_path(
        args.install_path, PurePosixPath(args.install_path.rstrip("/")).name
    )
    for target in (output, archive):
        require(
            not target.exists() and not target.is_symlink(),
            "Output already exists: " + str(target),
        )
    output, archive = output.resolve(), archive.resolve()
    for source in (root, *apps):
        for target in (output, archive):
            require(
                source != target
                and source not in target.parents
                and target not in source.parents,
                "Keep outputs separate from stock inputs.",
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".DR2Runtime-", dir=output.parent
    ) as temporary:
        stage = Path(temporary) / output.name
        prepare(root, stage, destination, apps)
        packed = Path(temporary) / "runtime.tar.gz"
        package(stage, packed, "pbs-dr2")
        stage.rename(output)
        packed.rename(archive)
    print(output)
    print(archive)


if __name__ == "__main__":
    main()
