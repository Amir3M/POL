#!/usr/bin/env python3
"""Verify the signed APK's first launch and record the disconnected Android home."""

import argparse
import re
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "com.polvpn.app.debug"
ACTIVITY = f"{PACKAGE}/com.arman.firefoxvpn.MainActivity"
UI_DUMP = "/data/local/tmp/amir-vpn-home.xml"
BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


def adb(*args, timeout=20, check=True):
    return subprocess.run(
        ["adb", *map(str, args)],
        capture_output=True,
        timeout=timeout,
        check=check,
    )


def hierarchy():
    adb("shell", "uiautomator", "dump", UI_DUMP, check=False)
    data = adb("exec-out", "cat", UI_DUMP, check=False).stdout
    try:
        return ET.fromstring(data)
    except ET.ParseError:
        return None


def app_nodes(root):
    if root is not None:
        for node in root.iter("node"):
            if node.get("package") == PACKAGE:
                yield node


def labels(node):
    return (node.get("text", ""), node.get("content-desc", ""))


def tap(node):
    match = BOUNDS.fullmatch(node.get("bounds", ""))
    if match is None:
        raise RuntimeError("Android control has no tappable bounds")
    left, top, right, bottom = map(int, match.groups())
    adb("shell", "input", "tap", (left + right) // 2, (top + bottom) // 2)


def open_home():
    deadline = time.monotonic() + 100
    started = False
    while time.monotonic() < deadline:
        nodes = list(app_nodes(hierarchy()))
        screen = "\n".join(value for node in nodes for value in labels(node))
        if "AMiR VPN" in screen and (
            "Disconnected" in screen or "Tap to connect" in screen
        ):
            return
        welcome = next((node for node in nodes if "Start" in labels(node)), None)
        if welcome is not None and not started:
            tap(welcome)
            started = True
        time.sleep(1)
    raise RuntimeError("Android did not display the disconnected AMiR VPN home")


def find_control(label):
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        for node in app_nodes(hierarchy()):
            if any(label in value.splitlines() for value in labels(node)):
                return node
        time.sleep(1)
    raise RuntimeError(f"Android did not display {label!r}")


def capture(path):
    data = adb("exec-out", "screencap", "-p").stdout
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("Android screenshot is not a PNG")
    path.write_bytes(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    if not adb("get-serialno").stdout.strip().startswith(b"emulator-"):
        raise RuntimeError("Select an Android emulator")
    args.out.mkdir(parents=True, exist_ok=True)
    adb("install", "-g", "-r", args.apk, timeout=150)
    try:
        adb("shell", "am", "start", "-W", "-n", ACTIVITY, timeout=45)
        open_home()
        capture(args.out / "android-home.png")
        tap(find_control("Share Proxy"))
        find_control("Enable Share Proxy?")
        capture(args.out / "android-share-proxy-confirmation.png")
        print("Verified the installed release APK and captured both Android screens.")
    except Exception:
        capture(args.out / "android-launch-failure.png")
        log = adb("logcat", "-d", "-t", "300", check=False)
        (args.out / "android-launch.log").write_bytes(log.stdout)
        raise
    finally:
        adb("shell", "am", "force-stop", PACKAGE, check=False)
        adb("shell", "rm", "-f", UI_DUMP, check=False)


if __name__ == "__main__":
    main()
