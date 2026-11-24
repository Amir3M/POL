#!/usr/bin/env bash
set -euo pipefail

# Run on an already booted AOSP emulator. ANDROID_SERIAL selects the emulator
# when more than one ADB target is already present.
exec python3 - "$@" <<'PY'
import argparse
from contextlib import suppress
import http.client
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


PACKAGE = "com.polvpn.app.debug"
ACTIVITY = f"{PACKAGE}/com.arman.firefoxvpn.MainActivity"
DUMP_PATH = f"/data/local/tmp/pol-tunnel-smoke-{os.getpid()}.xml"
HOST, PORT = "192.0.2.1", "8080"
PAYLOAD = b"P" * (256 * 1024)
UNKNOWN_QUOTA = "Test quota · Unknown"
FULL_QUOTA = "Test quota · 16.0 MB remaining of 16.0 MB"
QUOTA_AFTER_TRANSFER = "Test quota · 15.5 MB remaining of 16.0 MB"
BIDI_MARKS = str.maketrans("", "", "\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")


class SmokeFailure(Exception):
    pass


class ShellTransferUnavailable(Exception):
    pass


def adb(*args, data=None, timeout=15, check=True):
    completed = subprocess.run(
        ["adb", *args], input=data, capture_output=True, timeout=timeout, check=False,
    )
    if check and completed.returncode:
        raise SmokeFailure(f"adb {args[0]} failed (exit {completed.returncode})")
    return completed


def ui_nodes():
    # Ignore transient dumps during window transitions and retry on the next poll.
    try:
        dumped = adb("shell", "uiautomator", "dump", DUMP_PATH, timeout=12, check=False)
        if b"permission denied" in (dumped.stdout + dumped.stderr).lower():
            raise SmokeFailure("UIAutomator cannot write its temporary hierarchy on the emulator.")
        if dumped.returncode or b"dumped to:" not in dumped.stdout:
            return []
        xml = adb("exec-out", "cat", DUMP_PATH, check=False)
        return list(ET.fromstring(xml.stdout).iter("node")) if xml.returncode == 0 else []
    except (ET.ParseError, subprocess.TimeoutExpired):
        return []


def node_labels(node):
    for attribute in ("text", "content-desc"):
        label = " ".join(node.get(attribute, "").translate(BIDI_MARKS).split())
        if label:
            yield label


def find_label(nodes, expected):
    for node in nodes:
        if expected in node_labels(node):
            return node, expected
    return None


def wait_for(description, probe, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = probe()
        if result:
            return result
        time.sleep(0.35)
    raise SmokeFailure(f"Timed out waiting for {description}.")


def wait_for_label(expected):
    return wait_for(expected, lambda: find_label(ui_nodes(), expected))


def tap(node):
    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if bounds is None:
        raise SmokeFailure("The UI target has invalid bounds.")
    left, top, right, bottom = map(int, bounds.groups())
    if right <= left or bottom <= top:
        raise SmokeFailure("The UI target is outside the visible area.")
    adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))


def tap_label(label):
    def enabled_match():
        match = find_label(ui_nodes(), label)
        return match if match is not None and match[0].get("enabled") != "false" else None

    node, _ = wait_for(label, enabled_match)
    tap(node)


def launch():
    started = adb("shell", "am", "start", "-W", "-n", ACTIVITY, timeout=45)
    if b"Error" in started.stdout or b"Error" in started.stderr:
        raise SmokeFailure("The tunnel-test launcher could not start.")
    wait_for_label("Local tunnel test")


def process_id():
    process = adb("shell", "pidof", PACKAGE, check=False)
    if process.returncode not in (0, 1) or process.stderr:
        raise SmokeFailure("ADB could not inspect the tunnel-test process.")
    return process.stdout.strip()


def stop_process():
    wait_for("the running app process", process_id)
    adb("shell", "am", "force-stop", PACKAGE)
    wait_for("the app process to exit", lambda: not process_id(), seconds=12)


def restart():
    stop_process()
    launch()


def connect():
    tap_label("Connect")

    def next_state(button):
        nodes = ui_nodes()
        if button is not None:
            for node in nodes:
                if (node.get("package") == "com.android.vpndialogs"
                        and node.get("resource-id") == f"android:id/button{button}"):
                    tap(node)
                    return "consent"
        if find_label(nodes, "Android VPN · Test VPN failed"):
            raise SmokeFailure("Android reported a failed test VPN connection.")
        return "connected" if find_label(nodes, "Android VPN · Connected") else None

    result = wait_for("VPN consent or connection", lambda: next_state(2), seconds=60)
    if result == "consent":
        wait_for_label("Android VPN · Disconnected")
        check_diagnostics(
            "VPN connection: Disconnected",
            "TUN interface: Pending",
            "Last test issue: Android VPN permission was declined.",
        )
        print("Declining VPN consent left the test VPN off and appeared in Diagnostics.")
        tap_label("Connect")
        wait_for("VPN consent or connection", lambda: next_state(1), seconds=60)
        wait_for("Android VPN to connect", lambda: next_state(None), seconds=60)
    else:
        print("Android already granted VPN consent on this emulator.")
    wait_for_label("Proxy authorization · Authorized")
    print("Android VPN connected to the test fixture.")


class ResponseStream(io.BytesIO):
    def makefile(self, *_args, **_kwargs):
        return self


def fixture_request(method, path, payload=b""):
    request = (
        f"{method} {path} HTTP/1.1\r\nHost: {HOST}:{PORT}\r\n"
        f"Connection: close\r\nContent-Length: {len(payload)}\r\n\r\n"
    ).encode("ascii") + payload
    try:
        reply = adb(
            "shell", "-T", "toybox", "nc", "-n", "-w", "4", HOST, PORT,
            data=request, timeout=14, check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise ShellTransferUnavailable("the shell socket did not close") from error
    if not reply.stdout:
        raise ShellTransferUnavailable("the shell could not reach the fixture route")
    try:
        with http.client.HTTPResponse(ResponseStream(reply.stdout)) as response:
            response.begin()
            return response.status, response.getheader("X-POL-Tunnel-Proof"), response.read(len(PAYLOAD) + 1)
    except http.client.HTTPException as error:
        raise SmokeFailure("The shell received a malformed HTTP response.") from error


def check_shell_transfer(required):
    try:
        if adb("shell", "id", "-u").stdout.strip() != b"2000":
            raise ShellTransferUnavailable("ADB is not running as the distinct shell UID")
        applets = adb("shell", "toybox", check=False).stdout.split()
        if b"nc" not in applets:
            raise ShellTransferUnavailable("toybox nc is unavailable")
        status, proof, page = fixture_request("GET", "/")
    except ShellTransferUnavailable as error:
        if required:
            raise SmokeFailure(f"Required shell transfer unavailable: {error}.") from error
        print(f"Shell transfer skipped: {error}.")
        return False

    if status != 200 or not proof or b"POL tunnel fixture response" not in page:
        raise SmokeFailure("The shell received an unexpected HTTP response.")
    # Once the fixture responded, any transfer or integrity failure is fatal.
    status, download_proof, data = fixture_request("GET", "/download")
    if status != 200 or download_proof != proof or data != PAYLOAD:
        raise SmokeFailure("The fixture download did not return the expected 256 KiB.")
    status, upload_proof, uploaded = fixture_request("POST", "/upload", PAYLOAD)
    if status != 200 or upload_proof != proof or uploaded != str(len(PAYLOAD)).encode("ascii"):
        raise SmokeFailure("The fixture did not accept the 256 KiB upload.")
    wait_for_label("Test transfer · Upload and download verified")
    wait_for_label(QUOTA_AFTER_TRANSFER)
    print("Shell UID uploaded and downloaded 256 KiB through the fixture.")
    return True


def check_diagnostics(*expected):
    tap_label("Diagnostics")
    expected = ("Mode: Local tunnel test", *expected)

    def matches():
        text = " ".join(label for node in ui_nodes() for label in node_labels(node))
        return all(line in text for line in expected)

    wait_for("the fixture stages in Diagnostics", matches)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")
    wait_for_label("Local tunnel test")


def run(apk, require_shell_transfer):
    # This test installs an APK and accepts VPN consent. Restrict it to emulators.
    serial = adb("get-serialno").stdout.strip()
    if not serial.startswith(b"emulator-"):
        raise SmokeFailure("Select a booted Android emulator using ANDROID_SERIAL.")
    if adb("shell", "getprop", "sys.boot_completed").stdout.strip() != b"1":
        raise SmokeFailure("The Android emulator has not finished booting.")

    apk = str(apk.resolve())
    try:
        # Runtime permissions prevent the notifications prompt from interrupting
        # the test. Android's separate VPN consent is exercised through its UI.
        adb("install", "-r", "-g", apk, timeout=150)
        launch()
        wait_for_label("Test session · Signed out")
        tap_label("Start test session")
        wait_for_label("Test session · Ready")
        wait_for_label(UNKNOWN_QUOTA)
        restart()
        wait_for_label("Test session · Restored")
        wait_for_label(UNKNOWN_QUOTA)
        print("Test session restored after process exit. Quota is unknown before connecting.")

        stop_process()
        adb("install", "-r", apk, timeout=150)
        launch()
        wait_for_label("Test session · Restored")
        wait_for_label(UNKNOWN_QUOTA)
        print("Test session restored after reinstalling the identical APK in place.")

        connect()
        wait_for_label(FULL_QUOTA)
        tap_label("Renew test session")
        wait_for_label("Test session · Renewed")
        wait_for_label(FULL_QUOTA)
        print("Test session renewed and quota returned.")

        transferred = check_shell_transfer(require_shell_transfer)
        expected = [
            "VPN connection: Connected",
            "TUN interface: Established",
            "Proxy authorization: Authorized",
            "Authentication: Renewed",
        ]
        if transferred:
            expected.extend((
                "Test transfer: Upload and download verified",
                f"Test upload bytes: {len(PAYLOAD)}",
                f"Test download bytes: {len(PAYLOAD)}",
            ))
        check_diagnostics(*expected)
        tap_label("Disconnect")
        wait_for_label("Android VPN · Disconnected")
        check_diagnostics("VPN connection: Disconnected", "TUN interface: Pending")
        tap_label("End test session")
        wait_for_label("Test session · Signed out")
        restart()
        wait_for_label("Test session · Signed out")
        wait_for_label("Test quota · Unavailable")
        check_diagnostics("Authentication: Signed out", "Quota: Unavailable")
        print("The VPN disconnected and the session remained signed out after process exit.")
    finally:
        with suppress(OSError, subprocess.TimeoutExpired):
            adb("shell", "am", "force-stop", PACKAGE, check=False)
        with suppress(OSError, subprocess.TimeoutExpired):
            adb("shell", "rm", "-f", DUMP_PATH, check=False)


parser = argparse.ArgumentParser(
    prog="smoke-android-tunnel.sh",
    description="Smoke-test a signed POL tunnel-test APK on a booted AOSP emulator.",
)
parser.add_argument("apk", type=Path)
parser.add_argument("--require-shell-transfer", action="store_true", help="Fail if this emulator cannot route shell UID traffic.")
args = parser.parse_args()
if not args.apk.is_file():
    parser.error("apk must be an existing file")
try:
    run(args.apk, args.require_shell_transfer)
except (SmokeFailure, ShellTransferUnavailable, OSError, subprocess.TimeoutExpired) as error:
    print(f"Android tunnel smoke failed: {error}", file=sys.stderr)
    sys.exit(1)
print("Emulator smoke passed. Physical Android, provider authentication and internet egress remain separate tests.")
PY
