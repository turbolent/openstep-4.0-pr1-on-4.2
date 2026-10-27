"""Prepare stock OPENSTEP 4.0 PR1 MailViewer for OPENSTEP 4.2 Intel."""

import hashlib
import shutil
from pathlib import Path, PurePosixPath

from tools.common import EXECUTABLE_MODE, macho, require
from tools.common.macho import MachO
from tools.common.patch_macho import (
    add_app_icon,
    dylib_command,
    intel_slice,
    rewrite_libraries,
)

DEFAULT_INSTALL_PATH = "/me/Apps/MailViewerPR1.app"
EXPECTED_MAILVIEWER = "d1a6de9378966c3f213fc6b0a5b19d767607d05fa3b128c11c9a7b4546757973"
EXPECTED_MESSAGE = "454fdbfc4196311a0d2f40a0950b01ed61a39c9a988686eb2316b4fbac12c558"
EXPECTED_NEXTAPPS = "b8c702efc8779941c5a385a3b8030a8242f42bac648ead7b359bc507cdd63446"
APPKIT_A = "/NextLibrary/Frameworks/AppKit.framework/Versions/A/AppKit"
MESSAGE_A = "/NextLibrary/PrivateFrameworks/Message.framework/Versions/A/Message"
NEXTAPPS_A = "/NextLibrary/PrivateFrameworks/NeXTApps.framework/Versions/A/NeXTApps"
SUBSTRING_SELECTOR_ADDRESS = 0x1B0623AF
DEFAULTS_INSERT_CALL_ADDRESS = 0x1B04CE0B
DEFAULTS_INSERT_CALL = bytes.fromhex("e894300000")


def patch_message(data):
    # PR1's category replaces the 4.2 substring implementation with a call to
    # substringFromRange:. Keep its callers but give the legacy method its own
    # selector, so the adapter can call Foundation without recursing.
    data = bytearray(intel_slice(data))
    offset = MachO(data).offset(SUBSTRING_SELECTOR_ADDRESS)
    old, new = b"substringWithRange:\0", b"pr1_substringRange:\0"
    require(
        data[offset : offset + len(old)] == old and len(old) == len(new),
        "Unexpected Message substring selector.",
    )
    data[offset : offset + len(old)] = new
    # Defaults sharedInstance mutates NSUserDefaults' searchList in place.
    # 4.2 returns an immutable snapshot; MailViewerCompat installs the domain
    # using setSearchList: before the original application initializer runs.
    offset = MachO(data).offset(DEFAULTS_INSERT_CALL_ADDRESS)
    require(
        data[offset : offset + len(DEFAULTS_INSERT_CALL)] == DEFAULTS_INSERT_CALL,
        "Unexpected Message defaults insertion.",
    )
    data[offset : offset + len(DEFAULTS_INSERT_CALL)] = (
        macho.X86_NOP * len(DEFAULTS_INSERT_CALL)
    )
    return bytes(data)


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
        PurePosixPath(value).name == "MailViewerPR1.app",
        "Install path must end in MailViewerPR1.app.",
    )
    return str(PurePosixPath(value))


def inputs(source, message, nextapps):
    result = []
    for value, name, checksum, required in (
        (
            source,
            "MailViewer",
            EXPECTED_MAILVIEWER,
            ("app.tiff", "Info.plist", "English.lproj/MailViewer.nib/objects.nib"),
        ),
        (
            message,
            "Message",
            EXPECTED_MESSAGE,
            ("Message.defaults", "English.lproj/ProgressPanel.nib/objects.nib"),
        ),
        (nextapps, "NeXTApps", EXPECTED_NEXTAPPS, ("utilities.strings",)),
    ):
        path = Path(value).resolve()
        binary = (
            path / (name if name == "MailViewer" else "Versions/A/" + name)
            if path.is_dir()
            else path
        )
        resources = binary.parent / "Resources"
        require(binary.is_file(), "Missing stock input: " + str(binary))
        require(
            hashlib.sha256(binary.read_bytes()).hexdigest() == checksum,
            "Unsupported PR1 input: " + str(binary),
        )
        require(
            resources.is_dir(), "Missing stock Resources directory: " + str(resources)
        )
        require(
            not any(p.is_symlink() for p in resources.rglob("*")),
            "Resource symlinks are unsupported.",
        )
        for name in required:
            require(
                (resources / name).is_file(),
                "Missing stock resource: " + str(resources / name),
            )
        result.append((binary, resources))
    return result


def prepare_bundle(source, message, nextapps, output, destination=DEFAULT_INSTALL_PATH):
    destination = install_path(destination)
    sources = inputs(source, message, nextapps)
    output = Path(output).resolve()
    require(
        output.name == "MailViewerPR1.app", "Output must be named MailViewerPR1.app."
    )
    require(not output.exists(), "Output already exists: " + str(output))
    for binary, resources in sources:
        require(
            output != binary.parent
            and binary.parent not in output.parents
            and output not in binary.parents,
            "Output must be separate from stock inputs.",
        )
    replacements = {
        APPKIT_A: APPKIT_A.replace("/A/", "/B/"),
        MESSAGE_A: destination + "/Message.framework/Message",
        NEXTAPPS_A: destination + "/NeXTApps.framework/NeXTApps",
    }
    binary, resources = sources[0]
    data = rewrite_libraries(
        intel_slice(binary.read_bytes()),
        replacements,
        [dylib_command(destination + "/MailViewerCompat.dylib")],
    )
    data = add_app_icon(data, "MailViewerPR1", (resources / "app.tiff").read_bytes())
    output.mkdir(parents=True)
    shutil.copytree(resources, output / "Resources")
    (output / "MailViewerPR1").write_bytes(data)
    (output / "MailViewerPR1").chmod(EXECUTABLE_MODE)
    for (binary, resources), name in zip(sources[1:], ("Message", "NeXTApps")):
        framework = output / (name + ".framework")
        framework.mkdir()
        data = (
            patch_message(binary.read_bytes())
            if name == "Message"
            else intel_slice(binary.read_bytes())
        )
        (framework / name).write_bytes(rewrite_libraries(data, replacements))
        shutil.copytree(resources, framework / "Resources")
        for resource in resources.rglob("*"):
            if resource.is_file() and resource.name != "Info.plist":
                target = output / "Resources" / resource.relative_to(resources)
                require(
                    not target.exists(), "Framework resource collision: " + str(target)
                )
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(resource, target)
    info = (
        (output / "Resources/Info.plist")
        .read_bytes()
        .replace(b"NSExecutable = MailViewer;", b"NSExecutable = MailViewerPR1;")
        .replace(b"NSProviderName = MailViewer;", b"NSProviderName = MailViewerPR1;")
    )
    for name in ("Info.plist", "Info-nextstep.plist"):
        (output / "Resources" / name).write_bytes(info)
    return output
