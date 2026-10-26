"""Build the Power11 LSPosed/Vector module APK into module/Power11.apk.

Needs a JDK in PATH and the Android SDK (build-tools + a platform android.jar).
The SDK is found through ANDROID_HOME / ANDROID_SDK_ROOT or --sdk <path>.

Usage: python tools/build_app.py [--sdk <path>]
"""
import glob
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
STUBS = os.path.join(ROOT, "stubs")
BUILD = os.path.join(ROOT, "build")
OUT = os.path.join(ROOT, "module", "Power11.apk")
KEYSTORE = os.path.join(ROOT, "tools", "power11.keystore")
STOREPASS = "aosppowermenu"
ALIAS = "aosppowermenu"

EXE = ".exe" if os.name == "nt" else ""
BAT = ".bat" if os.name == "nt" else ""


def find_sdk():
    if "--sdk" in sys.argv:
        return sys.argv[sys.argv.index("--sdk") + 1]
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(var):
            return os.environ[var]
    sys.exit("Android SDK not found: set ANDROID_HOME or pass --sdk <path>")


def newest(pattern):
    found = sorted(glob.glob(pattern))
    if not found:
        sys.exit(f"not found: {pattern}")
    return found[-1]


def run(*cmd):
    subprocess.run([str(c) for c in cmd], check=True)


def ensure_keystore():
    """The signing key is not in git: create a local one on first build."""
    if os.path.exists(KEYSTORE):
        return
    run("keytool", "-genkeypair", "-keystore", KEYSTORE, "-storepass", STOREPASS,
        "-alias", ALIAS, "-keyalg", "RSA", "-keysize", "2048", "-validity", "36500",
        "-dname", "CN=Power11, O=Luigi Colantuono")


def module_version():
    prop = open(os.path.join(ROOT, "module", "module.prop"), encoding="utf-8").read()
    name = re.search(r"^version=v?(.+)$", prop, re.M).group(1).strip()
    code = re.search(r"^versionCode=(\d+)$", prop, re.M).group(1)
    return name, code


def main():
    sdk = find_sdk()
    tools = os.path.dirname(newest(os.path.join(sdk, "build-tools", "*", f"aapt2{EXE}")))
    android_jar = newest(os.path.join(sdk, "platforms", "android-*", "android.jar"))
    version_name, version_code = module_version()
    ensure_keystore()

    shutil.rmtree(BUILD, ignore_errors=True)
    classes = os.path.join(BUILD, "classes")
    os.makedirs(classes)

    # resources + manifest
    run(os.path.join(tools, f"aapt2{EXE}"), "compile", "--dir", os.path.join(APP, "res"), "-o", os.path.join(BUILD, "res.zip"))
    base = os.path.join(BUILD, "base.apk")
    run(os.path.join(tools, f"aapt2{EXE}"), "link", "-o", base, "-I", android_jar,
        "--manifest", os.path.join(APP, "AndroidManifest.xml"),
        "--min-sdk-version", "31", "--target-sdk-version", "35",
        "--version-code", version_code, "--version-name", version_name,
        "-A", os.path.join(APP, "assets"), os.path.join(BUILD, "res.zip"))

    # code: the Xposed stubs are compiled only to satisfy javac and left out of the dex
    sources = glob.glob(os.path.join(APP, "src", "**", "*.java"), recursive=True)
    sources += glob.glob(os.path.join(STUBS, "**", "*.java"), recursive=True)
    run("javac", "-nowarn", "-Xlint:-options", "-source", "8", "-target", "8",
        "-bootclasspath", os.pathsep.join([android_jar, os.path.join(tools, "core-lambda-stubs.jar")]),
        "-d", classes, *sources)
    app_classes = [p for p in glob.glob(os.path.join(classes, "**", "*.class"), recursive=True)
                   if os.sep + "robv" + os.sep not in p]
    run(os.path.join(tools, f"d8{BAT}"), "--release", "--min-api", "31", "--lib", android_jar,
        "--classpath", classes, "--output", BUILD, *app_classes)

    with zipfile.ZipFile(base, "a") as z:
        z.write(os.path.join(BUILD, "classes.dex"), "classes.dex")

    aligned = os.path.join(BUILD, "aligned.apk")
    run(os.path.join(tools, f"zipalign{EXE}"), "-p", "-f", "4", base, aligned)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    run(os.path.join(tools, f"apksigner{BAT}"), "sign", "--ks", KEYSTORE, "--ks-pass", f"pass:{STOREPASS}",
        "--ks-key-alias", ALIAS, "--out", OUT, aligned)
    if os.path.exists(OUT + ".idsig"):
        os.remove(OUT + ".idsig")
    print(f"{OUT} ({os.path.getsize(OUT) // 1024} KB)")


if __name__ == "__main__":
    main()
