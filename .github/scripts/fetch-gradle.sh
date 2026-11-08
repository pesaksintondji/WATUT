#!/usr/bin/env bash
# Download the Gradle distribution named in gradle-wrapper.properties ourselves (with retries
# and mirrors), check it against Gradle's official SHA-256, then point the wrapper(s) at it.
# Usage: fetch-gradle.sh <gradle-wrapper.properties>
set -euo pipefail
props="$1"
url=$(grep '^distributionUrl=' "$props" | cut -d= -f2- | sed 's/\\:/:/g')
file=$(basename "$url")
ver=$(echo "$file" | sed -E 's/^gradle-(.+)-(bin|all)\.zip$/\1/')
dest="${RUNNER_TEMP:-/tmp}/gradle-dist/$file"
mkdir -p "$(dirname "$dest")"

sha=""
for s in "https://services.gradle.org/distributions/$file.sha256" "https://downloads.gradle.org/distributions/$file.sha256"; do
  sha=$(curl -fsSL --retry 3 --retry-all-errors --max-time 60 "$s" | tr -d '[:space:]') && [ ${#sha} -eq 64 ] && break || sha=""
done
[ -n "$sha" ] || { echo "::error::Could not fetch official checksum for $file"; exit 1; }
echo "Expected SHA-256 for $file: $sha"

ok=""
if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then ok=1; echo "Already downloaded: $dest"; fi
for attempt in 1 2 3; do
  [ -n "$ok" ] && break
  for src in "$url" \
             "https://downloads.gradle.org/distributions/$file" \
             "https://mirrors.cloud.tencent.com/gradle/$file" \
             "https://mirrors.aliyun.com/gradle/distributions/v$ver/$file"; do
    echo "Attempt $attempt: $src"
    if curl -fsSL --max-time 600 -o "$dest" "$src" && echo "$sha  $dest" | sha256sum -c -; then ok=1; break 2; fi
    rm -f "$dest"
  done
  sleep $((attempt * 10))
done
[ -n "$ok" ] || { echo "::error::Could not download $file from any source"; exit 1; }

for p in "$props"; do
  sed -i -E "s|^distributionUrl=.*|distributionUrl=file\\\\:$dest|; /^distributionSha256Sum=/d; /^validateDistributionUrl=/d" "$p"
  echo "distributionSha256Sum=$sha" >> "$p"
  echo "Patched $p:"; grep -E '^distribution(Url|Sha256Sum)=' "$p"
done
