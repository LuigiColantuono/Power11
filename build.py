"""Package module/ into a flashable zip.

Usage: python build.py            (uses the existing APK and banner)
       python build.py --all      (rebuilds the Vector APK and banner first)
"""
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(ROOT, "module")
EXECUTABLE = {"customize.sh", "power11.sh", "post-fs-data.sh", "service.sh", "action.sh", "uninstall.sh",
              "watcher.sh", "p11cmd.sh"}


def main():
    if "--all" in sys.argv:
        subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "build_app.py")], check=True)
        subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "make_banner.py")], check=True)

    prop = open(os.path.join(MODULE, "module.prop"), encoding="utf-8").read()
    version = re.search(r"^version=(.+)$", prop, re.M).group(1).strip()
    out = os.path.join(ROOT, f"Power11_{version}.zip")

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(MODULE):
            for f in sorted(files):
                path = os.path.join(root, f)
                arc = os.path.relpath(path, MODULE).replace(os.sep, "/")
                data = open(path, "rb").read()
                if f.endswith((".sh", ".prop", ".html")):
                    assert b"\r" not in data, f"CRLF line endings in {arc}"
                info = zipfile.ZipInfo(arc)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = (0o755 if f in EXECUTABLE else 0o644) << 16
                z.writestr(info, data)
    print(f"{out} ({os.path.getsize(out) // 1024} KB)")


if __name__ == "__main__":
    main()
