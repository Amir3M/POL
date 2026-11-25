#!/usr/bin/env bash
set -euo pipefail

app="$1"
screenshots="$(realpath -m "$2")"
scale="$3"
scratch="$(mktemp -d)"
app_pid=''
wm_pid=''
cleanup() {
  if [[ -n "$app_pid" ]]; then kill "$app_pid" 2>/dev/null || true; fi
  if [[ -n "$wm_pid" ]]; then kill "$wm_pid" 2>/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$screenshots" "$scratch/profile"
# A blank profile displays the welcome page on a light, unclipped canvas.
printf '%s\n' '{"theme":"light","language":"en"}' > "$scratch/profile/app-settings.json"
if [[ "$app" == *.tar.gz ]]; then
  tar -xzf "$app" -C "$scratch"
  app="$scratch/amir-vpn/arman-vpn"
fi
openbox >"$screenshots/openbox-$scale.log" 2>&1 &
wm_pid=$!
export GDK_BACKEND=x11 GDK_SCALE="$scale" LIBGL_ALWAYS_SOFTWARE=1
"$app" --data-dir="$scratch/profile" \
  >"$screenshots/app-$scale.log" 2>&1 &
app_pid=$!
if ! window="$(timeout 35 xdotool search --sync --onlyvisible --name '^AMiR VPN$' | sed -n '1p')"; then
  cat "$screenshots/app-$scale.log" "$screenshots/openbox-$scale.log" >&2
  exit 1
fi
sleep 2

capture() {
  import -window "$window" "$screenshots/$1-$scale.png"
  /usr/bin/python3 - "$screenshots/$1-$scale.png" "$1" <<'PY'
import sys
from PIL import Image, ImageStat

frame = Image.open(sys.argv[1]).convert("L")
width, height = frame.size
print(f"{sys.argv[2]}: {width}×{height}")
if sys.argv[2] == "maximized" and (width < 1750 or height < 1450):
    raise SystemExit("window did not maximize")
# The welcome backdrop should be drawn in every quadrant. A shifted
# Flutter surface leaves one or more of these samples on the black canvas.
for x, y in ((.15, .20), (.85, .20), (.15, .80), (.85, .80)):
    px, py = int(x * width), int(y * height)
    patch = frame.crop((px - 12, py - 12, px + 12, py + 12))
    if ImageStat.Stat(patch).mean[0] < 64:
        raise SystemExit(f"blank window region at ({x:.0%}, {y:.0%})")
PY
}
capture windowed
printf -v wm_window '0x%x' "$window"
wmctrl -ir "$wm_window" -b add,maximized_vert,maximized_horz
sleep 2
capture maximized
