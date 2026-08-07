#!/usr/bin/env bash

set -Eeuo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "usage: inspect-node-image.sh <registry/image:tag>" >&2
  exit 1
fi

: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
: "${EXPECTED_COMMIT:?EXPECTED_COMMIT is required}"
: "${EXPECTED_UPSTREAM_VERSION:?EXPECTED_UPSTREAM_VERSION is required}"
: "${EXPECTED_UPSTREAM_COMMIT:?EXPECTED_UPSTREAM_COMMIT is required}"

image_ref="$1"
manifest_file="$(mktemp)"
error_file="$(mktemp)"
cleanup() {
  rm -f "$manifest_file" "$error_file"
}
trap cleanup EXIT

if ! docker buildx imagetools inspect --raw "$image_ref" \
  >"$manifest_file" 2>"$error_file"; then
  error_text="$(tr '[:upper:]' '[:lower:]' <"$error_file")"
  if [[ "$error_text" == *"manifest unknown"* ||
        "$error_text" == *"name unknown"* ||
        "$error_text" == *"no such manifest"* ||
        "$error_text" == *": not found"* ||
        "$error_text" == *"404 not found"* ]]; then
    echo "Image does not exist: $image_ref"
    exit 2
  fi

  echo "Failed to inspect $image_ref; refusing to treat the error as a missing image." >&2
  cat "$error_file" >&2
  exit 1
fi

if ! jq -e '
  [
    .manifests[]?
    | {os: .platform.os, architecture: .platform.architecture}
  ]
  | sort_by(.architecture)
  == [
    {os: "linux", architecture: "amd64"},
    {os: "linux", architecture: "arm64"}
  ]
' "$manifest_file" >/dev/null; then
  echo "$image_ref must contain exactly linux/amd64 and linux/arm64." >&2
  exit 1
fi

image_repository="$image_ref"
if [[ "${image_ref##*/}" == *:* ]]; then
  image_repository="${image_ref%:*}"
fi

for architecture in amd64 arm64; do
  digest="$({
    jq -er --arg architecture "$architecture" '
      .manifests[]
      | select(
          .platform.os == "linux"
          and .platform.architecture == $architecture
        )
      | .digest
    ' "$manifest_file"
  })"
  platform_ref="$image_repository@$digest"

  docker pull --platform "linux/$architecture" "$platform_ref" >/dev/null

  actual_architecture="$(
    docker image inspect --format '{{.Architecture}}' "$platform_ref"
  )"
  test "$actual_architecture" = "$architecture" || {
    echo "$platform_ref reports architecture $actual_architecture." >&2
    exit 1
  }

  entrypoint="$(
    docker image inspect --format '{{json .Config.Entrypoint}}' "$platform_ref"
  )"
  test "$entrypoint" = '["/usr/local/bin/one-node-node"]' || {
    echo "$platform_ref has unexpected entrypoint $entrypoint." >&2
    exit 1
  }

  while IFS='|' read -r label expected; do
    actual="$(
      docker image inspect \
        --format "{{ index .Config.Labels \"$label\" }}" \
        "$platform_ref"
    )"
    test "$actual" = "$expected" || {
      echo "$platform_ref label $label is $actual, expected $expected." >&2
      exit 1
    }
  done <<EOF
org.opencontainers.image.version|$EXPECTED_VERSION
org.opencontainers.image.revision|$EXPECTED_COMMIT
io.one-node.upstream.version|$EXPECTED_UPSTREAM_VERSION
io.one-node.upstream.commit|$EXPECTED_UPSTREAM_COMMIT
EOF

  expected_version_output="one-node-node $EXPECTED_VERSION ($EXPECTED_COMMIT); sing-box $EXPECTED_UPSTREAM_VERSION ($EXPECTED_UPSTREAM_COMMIT)"
  actual_version_output="$(
    docker run --rm --platform "linux/$architecture" "$platform_ref" version
  )"
  test "$actual_version_output" = "$expected_version_output" || {
    echo "$platform_ref returned unexpected version metadata." >&2
    exit 1
  }
done

echo "Validated linux/amd64 and linux/arm64 image $image_ref"
