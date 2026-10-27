"""Package DR2 ports with native compatibility sources."""

import gzip
import io
import shutil
import tarfile
import tempfile
from pathlib import Path

from . import EXECUTABLE_MODE, FILE_MODE, require
from .dr2 import install_path


def package(bundle, archive, app_name):
    with archive.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(
                fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT
            ) as tar:
                for path in sorted(bundle.rglob("*")):
                    if not path.is_file():
                        continue
                    name = path.relative_to(bundle).as_posix()
                    info = tarfile.TarInfo(name)
                    data = path.read_bytes()
                    info.size = len(data)
                    info.mode = EXECUTABLE_MODE if name == app_name else FILE_MODE
                    tar.addfile(info, io.BytesIO(data))


def build_bundle(
    *, sources, input_roots, output, archive, destination, app_name, prepare, native_sources
):
    bundle_name = app_name + ".app"
    destination = install_path(destination, bundle_name)
    output, archive = Path(output).absolute(), Path(archive).absolute()
    for target in (output, archive):
        require(
            not target.exists() and not target.is_symlink(),
            "Output already exists: " + str(target),
        )
    output, archive = output.resolve(), archive.resolve()
    require(output.name == bundle_name, "Output must be named " + bundle_name + ".")
    require(
        output not in archive.parents and archive != output,
        "Archive must be outside the app.",
    )
    for root in (Path(path).resolve() for path in input_roots):
        for target in (output, archive):
            require(
                root != target
                and root not in target.parents
                and target not in root.parents,
                "Outputs must be separate from stock inputs.",
            )
    output.parent.mkdir(parents=True, exist_ok=True)
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="." + app_name + "-", dir=output.parent
    ) as staging:
        app = prepare(sources, Path(staging) / bundle_name, destination)
        native = app / "Compatibility"
        native.mkdir()
        for name, source in native_sources.items():
            target = native / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        # The native compiler checks this path before creating the dylib.
        (native / "install-path").write_text(
            destination + "\n", encoding="ascii", newline="\n"
        )
        with tempfile.TemporaryDirectory(
            prefix="." + app_name + "-", dir=archive.parent
        ) as packed:
            temporary_archive = Path(packed) / "app.tar.gz"
            package(app, temporary_archive, app_name)
            app.rename(output)
            temporary_archive.rename(archive)
    return output, archive
