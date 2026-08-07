#!/usr/bin/env bash

set -Eeuo pipefail

: "${IMAGE:?IMAGE is required}"
: "${IMAGE_REVISION_TAG:?IMAGE_REVISION_TAG is required}"
: "${IMAGE_RC_TAG:?IMAGE_RC_TAG is required}"
: "${IMAGE_BUILD_TAG:?IMAGE_BUILD_TAG is required}"
: "${IMAGE_SOURCE:?IMAGE_SOURCE is required}"
: "${IMAGE_DESCRIPTION:?IMAGE_DESCRIPTION is required}"
: "${IMAGE_REVISION:?IMAGE_REVISION is required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION is required}"
: "${EXPECTED_COMMIT:?EXPECTED_COMMIT is required}"
: "${EXPECTED_UPSTREAM_VERSION:?EXPECTED_UPSTREAM_VERSION is required}"
: "${EXPECTED_UPSTREAM_COMMIT:?EXPECTED_UPSTREAM_COMMIT is required}"

should_build="${SHOULD_BUILD:-false}"
revision_ref="$IMAGE:$IMAGE_REVISION_TAG"
rc_ref="$IMAGE:$IMAGE_RC_TAG"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
inspect_script="$script_dir/inspect-node-image.sh"

inspect_image() {
  if bash "$inspect_script" "$1"; then
    return 0
  else
    return $?
  fi
}

platform_fingerprint() {
  docker buildx imagetools inspect --raw "$1" |
    jq -er '
      [
        .manifests[]
        | select(
            .platform.os == "linux"
            and (
              .platform.architecture == "amd64"
              or .platform.architecture == "arm64"
            )
          )
        | "\(.platform.architecture)=\(.digest)"
      ]
      | sort
      | join(",")
    '
}

if [ "$should_build" = "true" ]; then
  if inspect_image "$revision_ref"; then
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
      --annotation "index:org.opencontainers.image.version=$EXPECTED_VERSION" \
      -t "$revision_ref" \
      "$IMAGE:$IMAGE_BUILD_TAG"
    inspect_image "$revision_ref"
  fi
else
  inspect_image "$revision_ref"
fi

revision_fingerprint="$(platform_fingerprint "$revision_ref")"
if inspect_image "$rc_ref"; then
  rc_fingerprint="$(platform_fingerprint "$rc_ref")"
  if [ "$rc_fingerprint" != "$revision_fingerprint" ]; then
    echo "$rc_ref already points to a different multi-architecture image." >&2
    exit 1
  fi
  echo "$rc_ref already points to the requested image; keeping it unchanged."
else
  status=$?
  if [ "$status" -ne 2 ]; then
    exit "$status"
  fi
  docker buildx imagetools create \
    --annotation "index:org.opencontainers.image.description=$IMAGE_DESCRIPTION" \
    --annotation "index:org.opencontainers.image.revision=$IMAGE_REVISION" \
    --annotation "index:org.opencontainers.image.source=$IMAGE_SOURCE" \
    --annotation "index:org.opencontainers.image.version=$EXPECTED_VERSION" \
    -t "$rc_ref" \
    "$revision_ref"
  inspect_image "$rc_ref"
fi

echo "Published immutable image $revision_ref"
echo "Published immutable RC image $rc_ref"
