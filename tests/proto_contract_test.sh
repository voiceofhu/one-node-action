#!/bin/sh
set -eu

ACTION_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
SERVER_DIR=${ONE_NODE_SERVER_DIR:-"$ACTION_ROOT/../one-node-server"}
NODE_DIR=${ONE_NODE_NODE_DIR:-"$ACTION_ROOT/../one-node-node"}

fail() {
	printf '%s\n' "proto contract: $*" >&2
	exit 1
}

for command in git go cmp sed awk mktemp; do
	command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done

[ -d "$SERVER_DIR" ] || fail "Server sibling is missing: $SERVER_DIR"
[ -d "$NODE_DIR" ] || fail "Node sibling is missing: $NODE_DIR"
git -C "$SERVER_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
	fail "Server sibling is not a Git worktree: $SERVER_DIR"
git -C "$NODE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
	fail "Node sibling is not a Git worktree: $NODE_DIR"

SERVER_DIR=$(CDPATH='' cd -- "$SERVER_DIR" && pwd)
NODE_DIR=$(CDPATH='' cd -- "$NODE_DIR" && pwd)
MANIFEST="$NODE_DIR/one/control/proto-source.json"
[ -f "$MANIFEST" ] || fail "Node protocol manifest is missing: $MANIFEST"

manifest_value() {
	key=$1
	values=$(sed -n 's/^[[:space:]]*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)"[[:space:]]*,\{0,1\}[[:space:]]*$/\1/p' "$MANIFEST")
	count=$(printf '%s\n' "$values" | awk 'NF { count++ } END { print count + 0 }')
	[ "$count" -eq 1 ] || fail "manifest must contain exactly one string value for $key"
	printf '%s\n' "$values"
}

server_commit=$(manifest_value server_commit)
proto_path=$(manifest_value proto_path)
proto_sha256=$(manifest_value proto_sha256)
generated_path=$(manifest_value generated_path)
generated_sha256=$(manifest_value generated_sha256)
generator=$(manifest_value generator)

case "$server_commit" in
	*[!0-9a-f]*|'') fail "manifest server_commit must be a lowercase hexadecimal commit" ;;
esac
[ "${#server_commit}" -eq 40 ] || fail "manifest server_commit must contain 40 characters"
for digest in "$proto_sha256" "$generated_sha256"; do
	case "$digest" in
		*[!0-9a-f]*|'') fail "manifest SHA-256 values must be lowercase hexadecimal" ;;
	esac
	[ "${#digest}" -eq 64 ] || fail "manifest SHA-256 values must contain 64 characters"
done
[ "$proto_path" = "api/node_control.proto" ] || fail "unexpected canonical proto path: $proto_path"
[ "$generated_path" = "api/gen/go/control/v2/node_control.pb.go" ] ||
	fail "unexpected canonical generated path: $generated_path"
[ "$generator" = "p01-protogen/v1 github.com/golang/protobuf/protoc-gen-go@v1.5.4" ] ||
	fail "unexpected generator pin: $generator"

git -C "$SERVER_DIR" cat-file -e "$server_commit^{commit}" 2>/dev/null ||
	fail "manifest Server commit is not present in the Server checkout: $server_commit"
server_head=$(git -C "$SERVER_DIR" rev-parse HEAD)
git -C "$SERVER_DIR" merge-base --is-ancestor "$server_commit" "$server_head" 2>/dev/null ||
	fail "Server checkout $server_head does not descend from manifest commit $server_commit"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/one-node-proto-contract.XXXXXX")
trap 'rm -rf -- "$TEMP_DIR"' EXIT HUP INT TERM
GOCACHE="$TEMP_DIR/go-build"
export GOCACHE

git -C "$SERVER_DIR" show "$server_commit:$proto_path" >"$TEMP_DIR/canonical.proto" ||
	fail "cannot read canonical proto at manifest Server commit"
git -C "$SERVER_DIR" show "$server_commit:$generated_path" >"$TEMP_DIR/canonical.pb.go" ||
	fail "cannot read canonical generated binding at manifest Server commit"

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{ print $1 }'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{ print $1 }'
	else
		fail "sha256sum or shasum is required"
	fi
}

assert_sha256() {
	label=$1
	path=$2
	expected=$3
	[ -f "$path" ] || fail "$label is missing: $path"
	actual=$(sha256_file "$path")
	[ "$actual" = "$expected" ] || fail "$label SHA-256 is $actual, expected $expected"
}

SERVER_PROTO="$SERVER_DIR/$proto_path"
SERVER_GENERATED="$SERVER_DIR/$generated_path"
NODE_GENERATED="$NODE_DIR/one/control/gen/control/v2/node_control.pb.go"
assert_sha256 "canonical proto" "$TEMP_DIR/canonical.proto" "$proto_sha256"
assert_sha256 "canonical generated binding" "$TEMP_DIR/canonical.pb.go" "$generated_sha256"
assert_sha256 "Server proto" "$SERVER_PROTO" "$proto_sha256"
assert_sha256 "Server generated binding" "$SERVER_GENERATED" "$generated_sha256"
assert_sha256 "Node generated binding" "$NODE_GENERATED" "$generated_sha256"
cmp -s "$SERVER_GENERATED" "$NODE_GENERATED" ||
	fail "Server and Node generated bindings are not byte-identical"

tool_version=$(cd "$SERVER_DIR" && go run -mod=readonly ./tools/p01-protogen -version)
[ "$tool_version" = "$generator" ] || fail "generator reports an unexpected version: $tool_version"
plugin_version=$(awk '$1 == "github.com/golang/protobuf" { print $2 }' \
	"$SERVER_DIR/tools/p01-protogen/plugin.mod")
[ "$plugin_version" = "v1.5.4" ] || fail "combined Go/gRPC plugin is not pinned to v1.5.4"

(cd "$SERVER_DIR" && go build -mod=readonly \
	-modfile=tools/p01-protogen/plugin.mod \
	-o "$TEMP_DIR/protoc-gen-go-grpc" \
	github.com/golang/protobuf/protoc-gen-go)
(cd "$SERVER_DIR" && go run -mod=readonly ./tools/p01-protogen \
	-plugin "$TEMP_DIR/protoc-gen-go-grpc" -check)
(cd "$SERVER_DIR" && go test -mod=readonly -count=1 \
	./tools/p01-protogen ./api/gen/go/control/v2)
(cd "$SERVER_DIR" && go test -mod=readonly -count=1 ./internal/nodecontrol \
	-run '^Test(V2|Typed|BindingSnapshotCommand|PendingRevokeBinding)')
(cd "$NODE_DIR" && go test -mod=readonly -count=1 ./one/control)

printf '%s\n' "proto contract: Server $server_commit and Node generated bindings verified"
