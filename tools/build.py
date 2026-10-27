"""Build a supported PR1 or Rhapsody DR2 app for OPENSTEP 4.2 Intel."""

import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("dock", "viewer", "mailviewer", "mailviewer-dr2"):
        print(
            "Usage: python tools/build.py {dock|viewer|mailviewer|mailviewer-dr2} [build options]\n"
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
    else:
        from tools.MailViewerDR2.build import main as build_main
    build_main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
