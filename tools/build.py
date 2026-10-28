"""Build a supported OPENSTEP, Rhapsody, or Mac OS X app for OPENSTEP 4.2 Intel."""

import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def main():
    targets = (
        "dock",
        "viewer",
        "mailviewer",
        "mailviewer-dr2",
        "stickies-dr2",
        "viewer-dr2",
        "workspace-dr2",
        "runtime-dr2",
        "terminal-tiger",
        "terminal-snow-leopard",
    )
    if len(sys.argv) < 2 or sys.argv[1] not in targets:
        print(
            "Usage: python tools/build.py {" + "|".join(targets) + "} [build options]\n"
            "Use TARGET --help for required stock inputs."
        )
        return 0 if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help") else 2
    target = sys.argv.pop(1)
    if target == "dock":
        from tools.Dock.build import main as build_main
    elif target == "viewer":
        from tools.Viewer.build import main as build_main
    elif target == "mailviewer":
        from tools.MailViewer.build import main as build_main
    elif target == "mailviewer-dr2":
        from tools.MailViewerDR2.build import main as build_main
    elif target == "viewer-dr2":
        from tools.ViewerDR2.build import main as build_main
    elif target == "workspace-dr2":
        from tools.WorkspaceDR2.build import main as build_main
    elif target == "runtime-dr2":
        from tools.common.build_runtime_dr2 import main as build_main
    elif target == "terminal-tiger":
        from tools.TerminalTiger.build import main as build_main
    elif target == "terminal-snow-leopard":
        from tools.TerminalSnowLeopard.build import main as build_main
    else:
        from tools.StickiesDR2.build import main as build_main
    build_main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
