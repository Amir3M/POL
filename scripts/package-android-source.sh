#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/android-env.sh"

apk="$(realpath -- "${1:?Supply a verified POL APK}")"
out="$(dirname -- "$apk")"
commit="$(git -C "$POL_REPO_ROOT" rev-parse HEAD)"
git -C "$POL_REPO_ROOT" diff --quiet HEAD -- app core scripts ||
    pol_error "Package source from the clean build commit."
(cd -- "$out" && sha256sum --check "$(basename -- "$apk").sha256")

package_tmp="$(mktemp -d "$out/.android-source.XXXXXX")"
trap 'rm -rf -- "$package_tmp"' EXIT
notices="$package_tmp/notices"
mkdir -p "$notices/go"
(
    cd -- "$POL_REPO_ROOT"
    cp --parents LICENSE app/assets/flags/LICENSE core/internal/service/web/flags/LICENSE \
        app/assets/fonts/OFL.txt app/assets/fonts/Inter/OFL.txt "$notices"
    find app/android/hev-socks5-tunnel -type f -name LICENSE -exec cp --parents -t "$notices" {} +
    git archive --format=tar.gz --prefix=pol-vpn-source/ --output="$package_tmp/pol-vpn-source.tar.gz" "$commit"
)
unzip -p "$apk" assets/flutter_assets/NOTICES.Z | gzip -dc > "$notices/Flutter-NOTICES.txt"

# The binding generator contributes its Java and Go runtime to the AAR.
cp "$(go env GOROOT)/LICENSE" "$notices/go/LICENSE"
modules="$package_tmp/go-modules"
(
    cd -- "$POL_REPO_ROOT/core"
    for arch in arm64 arm amd64; do
        GOOS=android GOARCH="$arch" CGO_ENABLED=1 go list -deps \
            -f '{{with .Module}}{{if not .Main}}{{.Path}}{{"\t"}}{{.Version}}{{"\t"}}{{.Dir}}{{end}}{{end}}' ./mobile
    done
    go list -m -f '{{.Path}}{{"\t"}}{{.Version}}{{"\t"}}{{.Dir}}' golang.org/x/mobile
) | sed '/^$/d' | sort -u > "$modules"

while IFS=$'\t' read -r module version directory; do
    destination="$notices/go/$module@$version"
    mkdir -p "$destination"
    find "$directory" -maxdepth 1 -type f \( -iname 'license*' -o -iname 'notice*' -o -iname 'copying*' \) \
        -exec cp -t "$destination" {} +
    [[ -n "$(ls -A -- "$destination")" ]] || pol_error "No license files found for $module@$version."
done < "$modules"

# Inventory the already resolved runtime classpath for this APK's variant.
case "$(basename -- "$apk")" in
    pol-vpn-debug.apk) variant=debug ;;
    pol-vpn-release.apk) variant=release ;;
    *) pol_error "Supply pol-vpn-debug.apk or pol-vpn-release.apk." ;;
esac

android_notices="$notices/android"
mkdir -p "$android_notices"
cp -- "$POL_REPO_ROOT/docs/licenses/"* "$android_notices/"
cat > "$package_tmp/runtime-notices.init.gradle.kts" <<'GRADLE'
import org.gradle.api.artifacts.component.ModuleComponentIdentifier

gradle.projectsEvaluated {
    val app = rootProject.findProject(":app") ?: return@projectsEvaluated
    app.tasks.register("polAndroidRuntimeArtifacts") {
        doLast {
            val variant = app.providers.gradleProperty("polNoticeVariant").get()
            val runtime = app.configurations.getByName("${variant}RuntimeClasspath")
            val artifacts = runtime.incoming.artifactView {
                componentFilter { it is ModuleComponentIdentifier }
            }.artifacts.artifacts
            val rows = artifacts.map { artifact ->
                val id = artifact.id.componentIdentifier as ModuleComponentIdentifier
                "${id.group}:${id.module}:${id.version}\t${artifact.file.absolutePath}"
            }.sorted()
            check(rows.isNotEmpty()) { "The Android runtime classpath is empty." }
            app.file(app.providers.gradleProperty("polNoticeArtifacts").get())
                .writeText(rows.joinToString("\n", postfix = "\n"))
        }
    }
}
GRADLE
runtime_artifacts="$package_tmp/runtime-artifacts.tsv"
(
    cd -- "$POL_REPO_ROOT/app/android"
    ./gradlew --offline --console=plain --init-script "$package_tmp/runtime-notices.init.gradle.kts" \
        :app:polAndroidRuntimeArtifacts "-PpolNoticeVariant=$variant" \
        "-PpolNoticeArtifacts=$runtime_artifacts"
)

python3 - "$runtime_artifacts" "$android_notices" <<'PYNOTICES'
from io import BytesIO
from pathlib import Path, PurePosixPath
import re
import sys
from zipfile import ZipFile

artifacts, output = map(Path, sys.argv[1:])
approved_apache = set((output / "android-runtime-apache-2.0.txt").read_text().splitlines())
notice_name = re.compile(r"^(license|notice|copying|copyright)([._-].*)?$", re.IGNORECASE)
inventory = {}

def copy_notices(archive, target):
    for index, entry in enumerate(archive.infolist()):
        name = PurePosixPath(entry.filename).name
        is_notice = notice_name.fullmatch(name) or entry.filename.lower().startswith("meta-inf/licenses/")
        if not entry.is_dir() and is_notice:
            target.mkdir(parents=True, exist_ok=True)
            (target / f"{index}-{name}").write_bytes(archive.read(entry))

for row in artifacts.read_text().splitlines():
    coordinate, filename = row.split("\t", 1)
    artifact = Path(filename)
    if coordinate.startswith("io.flutter:"):
        license_file = "../Flutter-NOTICES.txt"
    elif coordinate in approved_apache:
        license_file = "APACHE-2.0.txt"
    else:
        raise SystemExit(f"Android runtime license requires review: {coordinate}")
    inventory[coordinate] = license_file
    target = output / "artifact-notices" / coordinate.replace(":", "/") / artifact.name
    with ZipFile(artifact) as archive:
        copy_notices(archive, target)
        if artifact.suffix == ".aar":
            for index, entry in enumerate(archive.infolist()):
                if entry.filename.endswith(".jar"):
                    with ZipFile(BytesIO(archive.read(entry))) as nested:
                        copy_notices(nested, target / f"nested-{index}")

(output / "runtime-dependencies.tsv").write_text(
    "Maven coordinate\tLicense file\n"
    + "".join(f"{coordinate}\t{license_file}\n" for coordinate, license_file in sorted(inventory.items()))
)
PYNOTICES

tar -czf "$package_tmp/pol-vpn-notices.tar.gz" -C "$package_tmp" notices
mv -- "$package_tmp/pol-vpn-source.tar.gz" "$package_tmp/pol-vpn-notices.tar.gz" "$out/"
