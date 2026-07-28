#!/usr/bin/env bash

set -Eeuo pipefail

: "${IMAGE:?IMAGE is required}"
: "${IMAGE_REVISION_TAG:?IMAGE_REVISION_TAG is required}"
: "${IMAGE_VERSION:?IMAGE_VERSION is required}"
: "${IMAGE_BUILD_TAG:?IMAGE_BUILD_TAG is required}"
: "${IMAGE_SOURCE:?IMAGE_SOURCE is required}"
: "${IMAGE_DESCRIPTION:?IMAGE_DESCRIPTION is required}"
: "${IMAGE_REVISION:?IMAGE_REVISION is required}"

should_build="${SHOULD_BUILD:-false}"
revision_ref="$IMAGE:$IMAGE_REVISION_TAG"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
inspect_script="$script_dir/inspect-node-image.sh"

inspect_revision() {
  if bash "$inspect_script" "$revision_ref"; then
    return 0
  else
    return $?
  fi
}

platform_digest() {
  docker buildx imagetools inspect --raw "$1" |
    jq -er '
      .manifests[]
      | select(
          .platform.os == "linux"
          and .platform.architecture == "amd64"
        )
      | .digest
    '
}

if [ "$should_build" = "true" ]; then
  if inspect_revision; then
    echo "$revision_ref was published by an earlier queued run; keeping it unchanged."
  else
    status=$?
    if [ "$status" -ne 2 ]; then
      exit "$status"
    fi
    docker buildx imagetools create \
      --annotation "index:org.opencontainers.image.description=$IMAGE_DESCRIPTION" \
      --annotation "index:org.opencontainers.image.revision=$IMAGE_REVISION" \
      --annotation "index:org.opencontainers.image.source=$IMAGE_SOURCE" \
      --annotation "index:org.opencontainers.image.version=$IMAGE_REVISION_TAG" \
      -t "$revision_ref" \
      "$IMAGE:$IMAGE_BUILD_TAG"
    bash "$inspect_script" "$revision_ref"
  fi
else
  bash "$inspect_script" "$revision_ref"
fi

version_ref="$IMAGE:$IMAGE_VERSION"
revision_digest="$(platform_digest "$revision_ref")"
if bash "$inspect_script" "$version_ref"; then
  version_digest="$(platform_digest "$version_ref")"
  if [ "$version_digest" != "$revision_digest" ]; then
    echo "$version_ref already points to a different linux/amd64 image." >&2
    exit 1
  fi
  echo "$version_ref already points to the requested image; keeping it unchanged."
else
  status=$?
  if [ "$status" -ne 2 ]; then
    exit "$status"
  fi
  docker buildx imagetools create \
    --annotation "index:org.opencontainers.image.description=$IMAGE_DESCRIPTION" \
    --annotation "index:org.opencontainers.image.revision=$IMAGE_REVISION" \
    --annotation "index:org.opencontainers.image.source=$IMAGE_SOURCE" \
    --annotation "index:org.opencontainers.image.version=$IMAGE_VERSION" \
    -t "$version_ref" \
    "$revision_ref"
fi

echo "Published immutable image $revision_ref"
echo "Published install image $version_ref"
