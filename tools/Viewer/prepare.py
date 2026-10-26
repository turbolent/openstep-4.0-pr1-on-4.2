"""Prepare stock OPENSTEP 4.0 PR1 Viewer for native 4.2 helper compilation."""

import hashlib
import shutil
from pathlib import Path, PurePosixPath

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.macho import MachO
from tools.common.pr1_macho import (
    add_app_icon,
    dylib_command,
    intel_slice,
    rewrite_libraries,
)

EXPECTED_VIEWER = "fb9635dae68a2e52df31cf7a104f9a0972c93ab7c1b29916352cd268b9add6c2"
EXPECTED_NEXTAPPS = "b8c702efc8779941c5a385a3b8030a8242f42bac648ead7b359bc507cdd63446"
DEFAULT_INSTALL_PATH = "/me/Apps/ViewerPR1.app"
APPKIT_A = "/NextLibrary/Frameworks/AppKit.framework/Versions/A/AppKit"
NEXTAPPS_A = "/NextLibrary/PrivateFrameworks/NeXTApps.framework/Versions/A/NeXTApps"
FOUNDATION_B = "/NextLibrary/Frameworks/Foundation.framework/Versions/B/Foundation"
BUNDLE_INFO_METHOD_LIST_ADDRESS = 0x7A248
BUNDLE_INFO_METHOD_LIST = bytes.fromhex("010000001f920800a46c0800b4840000")
TOOL_LAUNCH_ADDRESS = 0x164B3
TOOL_LAUNCH_ORIGINAL = bytes.fromhex(
    "8b5d148d45fc508b551052e839fdffff8945f483c40885c00f8408010000e862fcffff"
)
TOOL_LAUNCH_INITIALIZE_FIRST = bytes.fromhex(
    "e880fcffff8b5d148d45fc508b551052e834fdffff8945f483c40885c00f8403010000"
)
PR1_TOOL_SERVICE = b"Miniapp_boot_port\0"
VIEWER_TOOL_SERVICE = b"ViewerPR1_tools\0"
BACKGROUND_TOOLS = {
    "Compressor.tool",
    "FileMover.tool",
    "PermissionChanger.tool",
    "Sizer.tool",
    "ToolFinder.tool",
}
SEARCH_WRAPPER = (
    b"#!/bin/sh\n"
    b"unset DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH\n"
    b'exec /usr/lib/NextStep/Workspace.app/WM.app/search "$@"\n'
)
ALIASES = (
    "addresses.bundle",
    "compression.bundle",
    "Compressor.tool",
    "console",
    "encryption.bundle",
    "FileMover.tool",
    "inspectors.bundle",
    "preferences.bundle",
    "processes.bundle",
    "recycler.bundle",
    "Sizer.tool",
    "ToolFinder.tool",
)


def install_path(value):
    value = value.rstrip("/")
    require(
        value.startswith("/") and not value.startswith("//"),
        "Install path must be absolute.",
    )
    require(
        not any(p in (".", "..") for p in value.split("/")),
        "Invalid install path components.",
    )
    require(
        value.isascii() and value.isprintable(),
        "Install path must use printable ASCII.",
    )
    require(
        PurePosixPath(value).name == "ViewerPR1.app",
        "Install path must end in ViewerPR1.app.",
    )
    return str(PurePosixPath(value))


def inputs(source, nextapps):
    source, nextapps = Path(source).resolve(), Path(nextapps).resolve()
    binary = source / "Viewer" if source.is_dir() else source
    framework = nextapps / "Versions/A/NeXTApps" if nextapps.is_dir() else nextapps
    for path, expected in ((binary, EXPECTED_VIEWER), (framework, EXPECTED_NEXTAPPS)):
        require(path.is_file(), "Missing stock input: " + str(path))
        require(
            hashlib.sha256(path.read_bytes()).hexdigest() == expected,
            "Unsupported PR1 input: " + str(path) + "; expected SHA256 " + expected,
        )
    resources, framework_resources = (
        binary.parent / "Resources",
        framework.parent / "Resources",
    )
    for folder, required in (
        (
            resources,
            ("Viewer.tiff", "Info.plist", "English.lproj/Viewer.nib/objects.nib"),
        ),
        (framework_resources, ("utilities.strings",)),
    ):
        require(folder.is_dir(), "Missing stock resource directory: " + str(folder))
        require(
            not any(p.is_symlink() for p in folder.rglob("*")),
            "Resource symlinks are unsupported.",
        )
        for name in required:
            require(
                (folder / name).is_file(),
                "Missing stock resource: " + str(folder / name),
            )
    return binary, resources, framework, framework_resources


def patch_tool_service(data):
    # Workspace 4.2 already owns PR1's service name. Both Viewer and its tools
    # need a separate name so helper connections reach the correct application.
    require(data.count(PR1_TOOL_SERVICE) == 1, "Unexpected tool service name.")
    return data.replace(
        PR1_TOOL_SERVICE, VIEWER_TOOL_SERVICE.ljust(len(PR1_TOOL_SERVICE), b"\0")
    )


def patch_viewer(data, destination, icon):
    require(
        hashlib.sha256(data).hexdigest() == EXPECTED_VIEWER,
        "Unsupported Viewer binary.",
    )
    data = bytearray(patch_tool_service(intel_slice(data)))
    image = MachO(data)
    # Register the tool service before forking. PR1 forks first, so a fast
    # helper can look up the service before Viewer has created it.
    launch_offset = image.offset(TOOL_LAUNCH_ADDRESS)
    require(
        data[launch_offset : launch_offset + len(TOOL_LAUNCH_ORIGINAL)]
        == TOOL_LAUNCH_ORIGINAL,
        "Unexpected Viewer tool launch sequence.",
    )
    data[launch_offset : launch_offset + len(TOOL_LAUNCH_ORIGINAL)] = (
        TOOL_LAUNCH_INITIALIZE_FIRST
    )
    # PR1 supplies its own -[NSBundle infoDictionary]. On 4.2, bundlePath calls
    # infoDictionary, which calls bundlePath again until the stack overflows.
    # Remove only this category's one method; Foundation retains its native method.
    count_offset = image.offset(BUNDLE_INFO_METHOD_LIST_ADDRESS)
    require(
        data[count_offset : count_offset + len(BUNDLE_INFO_METHOD_LIST)]
        == BUNDLE_INFO_METHOD_LIST,
        "Unexpected NSBundle(potatoes) method list.",
    )
    macho.UINT32.pack_into(data, count_offset, 0)
    replacements = {
        APPKIT_A: APPKIT_A.replace("/A/", "/B/"),
        NEXTAPPS_A: destination + "/NeXTApps",
    }
    data = rewrite_libraries(
        data, replacements, [dylib_command(destination + "/ViewerCompat.dylib")]
    )
    return add_app_icon(data, "ViewerPR1", icon)


def prepare_bundle(source, nextapps, output, destination=DEFAULT_INSTALL_PATH):
    destination = install_path(destination)
    binary, resources, framework, framework_resources = inputs(source, nextapps)
    output = Path(output).resolve()
    require(output.name == "ViewerPR1.app", "Output must be named ViewerPR1.app.")
    require(not output.exists(), "Output already exists: " + str(output))
    for original in (binary.parent, framework.parent):
        require(
            output != original
            and original not in output.parents
            and output not in original.parents,
            "Output must be separate from stock inputs.",
        )
    patched = patch_viewer(
        binary.read_bytes(), destination, (resources / "Viewer.tiff").read_bytes()
    )
    replacements = {
        APPKIT_A: APPKIT_A.replace("/A/", "/B/"),
        NEXTAPPS_A: destination + "/NeXTApps",
    }
    output.mkdir(parents=True)
    shutil.copytree(resources, output / "Resources")
    for path in (output / "Resources").rglob("*"):
        if path.is_file() and path.read_bytes().startswith(
            (macho.FAT_MAGIC, macho.MACH_MAGIC_I386)
        ):
            data = intel_slice(path.read_bytes())
            extra_libraries = []
            remove_libraries = []
            if path.name in BACKGROUND_TOOLS:
                data = patch_tool_service(data)
                extra_libraries.append(dylib_command(destination + "/ToolCompat.dylib"))
                # ToolCompat loads Foundation itself. Replacing the direct load
                # leaves room in Compressor.tool's small Mach-O header.
                remove_libraries.append(FOUNDATION_B)
            path.write_bytes(
                rewrite_libraries(data, replacements, extra_libraries, remove_libraries)
            )
            path.chmod(EXECUTABLE_MODE)
    # NeXTApps' utilities and bubble-help images are looked up in the app bundle.
    for path in framework_resources.rglob("*"):
        if path.is_file() and path.name != "Info.plist":
            target = output / "Resources" / path.relative_to(framework_resources)
            require(not target.exists(), "Framework resource collision: " + str(target))
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    (output / "ViewerPR1").write_bytes(patched)
    (output / "ViewerPR1").chmod(EXECUTABLE_MODE)
    # PR1's root search alias has no target in this prerelease image. The 4.2
    # Workspace tool accepts the same filename/content search arguments.
    (output / "search").write_bytes(SEARCH_WRAPPER)
    (output / "search").chmod(EXECUTABLE_MODE)
    (output / "NeXTApps").write_bytes(
        rewrite_libraries(intel_slice(framework.read_bytes()), replacements)
    )
    info = (
        (output / "Resources/Info.plist")
        .read_bytes()
        .replace(b"NSExecutable = Viewer;", b"NSExecutable = ViewerPR1;")
    )
    for name in ("Info.plist", "Info-nextstep.plist"):
        (output / "Resources" / name).write_bytes(info)
    # Use regular copies locally. The install archive restores the resource
    # aliases as relative symbolic links.
    for name in ALIASES:
        src = output / "Resources" / name
        require(src.exists(), "Missing bundled tool: " + name)
        if src.is_dir():
            shutil.copytree(src, output / name)
        else:
            shutil.copyfile(src, output / name)
    return output
