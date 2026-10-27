"""Patch stock Rhapsody DR2 Intel Viewer for OPENSTEP 4.2."""

import hashlib
import shutil
from pathlib import Path

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.dr2 import WRAPPED_FUNCTIONS, install_path, patch_image
from tools.common.dr2_appsupport import patch_class_layouts
from tools.common.patch_macho import intel_slice, rewrite_libraries

APP_NAME = "ViewerDR2"
BUNDLE_NAME = APP_NAME + ".app"
STOCK_HASHES = {
    "Viewer": "9400d39d055c6841af250f50b64193ea3d24629b712b88194da974a5b3b34790",
    "AppSupport": "ff763cffaaa0a38d8cacc6cc0ad24c942a82393cc95d1af4e5a3cca02428095c",
}
DR2_FOUNDATION = "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation"
VIEWER_WRAPPERS = WRAPPED_FUNCTIONS | {"fgets", "fflush", "lstat", "readdir", "statfs"}
TOOL_LAUNCH_ADDRESS = 0x1812F
TOOL_LAUNCH_ORIGINAL = bytes.fromhex(
    "8b7d148d45fc508b551052e889fdffff8945f483c40885c00f8408010000e8b2fcffff"
)
TOOL_LAUNCH_INITIALIZE_FIRST = bytes.fromhex(
    "e8d0fcffff8b7d148d45fc508b551052e884fdffff8945f483c40885c00f8403010000"
)
STOCK_TOOL_SERVICE = b"Miniapp_boot_port\0"
VIEWER_TOOL_SERVICE = b"ViewerDR2_tools\0"
STOCK_STAT_SELECTOR = b"attributesWithStat:\0"
NATIVE_STAT_SELECTOR = b"attributesWithDR2:\0"
SEARCH_WRAPPER = (
    b"#!/bin/sh\n"
    b"unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH\n"
    b'exec /usr/lib/NextStep/Workspace.app/WM.app/search "$@"\n'
)


def inputs(source, appsupport):
    result = {}
    for name, root in (("Viewer", source), ("AppSupport", appsupport)):
        root = Path(root).resolve()
        binary = root / name
        if not binary.is_file():
            binary = root / "Versions/B" / name
        require(binary.is_file(), "Missing stock input: " + str(binary))
        require(
            hashlib.sha256(binary.read_bytes()).hexdigest() == STOCK_HASHES[name],
            "Unsupported DR2 input: " + str(binary),
        )
        resources = binary.parent / "Resources"
        if not resources.is_dir():
            resources = root / "Resources"
        require(resources.is_dir(), "Missing stock Resources directory: " + str(resources))
        require(
            not any(path.is_symlink() for path in resources.rglob("*")),
            "Resource symlinks are unsupported.",
        )
        result[name] = binary, resources
    return result


def patch_binary(data, name, destination):
    data = intel_slice(data)
    # The injected compatibility library supplies Foundation. Removing this
    # redundant command leaves room for its path in the small tool headers.
    data = rewrite_libraries(data, {}, remove=[DR2_FOUNDATION])
    data = patch_image(data, destination, {"AppSupport"}, VIEWER_WRAPPERS)
    if name == "AppSupport":
        data = patch_class_layouts(data)
    if name == APP_NAME:
        offset = macho.MachO(data).offset(TOOL_LAUNCH_ADDRESS)
        require(
            data[offset : offset + len(TOOL_LAUNCH_ORIGINAL)] == TOOL_LAUNCH_ORIGINAL,
            "Unexpected Viewer tool bootstrap code.",
        )
        data[offset : offset + len(TOOL_LAUNCH_ORIGINAL)] = TOOL_LAUNCH_INITIALIZE_FIRST
    if name.endswith(".tool") or name == "console":
        library = "RuntimeCompat.dylib" if name == "console" else "ToolCompat.dylib"
        data = rewrite_libraries(
            data, {destination + "/DR2Compat.dylib": destination + "/" + library}
        )
    for old, new in (
        (STOCK_TOOL_SERVICE, VIEWER_TOOL_SERVICE),
        (STOCK_STAT_SELECTOR, NATIVE_STAT_SELECTOR),
        (b"apps5_1.ppl\0", b"appsDR2.ppl\0"),
    ):
        data = data.replace(old, new.ljust(len(old), b"\0"))
    return data


def prepare_bundle(sources, output, destination):
    destination = install_path(destination, BUNDLE_NAME)
    output.mkdir()
    for name, (binary, resources) in sources.items():
        target = output if name == "Viewer" else output / "AppSupport.framework"
        target.mkdir(exist_ok=True)
        shutil.copytree(resources, target / "Resources")
        shutil.copyfile(binary, target / (APP_NAME if name == "Viewer" else name))
    for path in output.rglob("*"):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if data.startswith((macho.FAT_MAGIC, macho.MACH_MAGIC_I386)):
            data = patch_binary(data, path.name, destination)
            path.write_bytes(data)
            if macho.is_intel_image(data, macho.MH_EXECUTE):
                path.chmod(EXECUTABLE_MODE)
        elif path.name == "objects.nib":
            path.write_bytes(data.replace(b"ssii@@@@@", b"ssIi@@@@@"))
    resources = output / "Resources"
    info = (resources / "Info-nextstep.plist").read_bytes()
    for key in (b"NSExecutable", b"NSPortName"):
        info = info.replace(key + b" = Viewer;", key + b" = ViewerDR2;")
    info = info.replace(b"in Workspace", b"in Viewer DR2")
    for name in ("Info.plist", "Info-nextstep.plist"):
        (resources / name).write_bytes(info)
    # The native build generates this in OPENSTEP's serialization format.
    (resources / "default.apps5_1.table").unlink()
    for path in resources.iterdir():
        if path.suffix == ".bundle":
            shutil.copytree(path, output / path.name)
        elif path.suffix == ".tool" or path.name == "console":
            shutil.copyfile(path, output / path.name)
            (output / path.name).chmod(EXECUTABLE_MODE)
    (output / "search").write_bytes(SEARCH_WRAPPER)
    (output / "search").chmod(EXECUTABLE_MODE)
    return output
