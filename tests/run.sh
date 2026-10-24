#!/usr/bin/env bash
# End-to-end test with a local directory standing in for the server.
# Usage: tests/run.sh   (needs git and rclone)
set -euo pipefail

GE="$(cd "$(dirname "$0")/.." && pwd)/git-everywhere"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
SERVER="$TMP/server/htdocs"
FAILS=0

ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }
check() {
	local desc=$1; shift
	if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}
same() {
	local desc=$1 expected=$2 actual=$3
	if [ "$expected" = "$actual" ]; then ok "$desc"; else fail "$desc: expected '$expected', got '$actual'"; fi
}

mkdir -p "$SERVER/sub" "$SERVER/cache"
echo "<?php echo 'v1';" >"$SERVER/index.php"
echo "hello" >"$SERVER/sub/page.html"
echo "tmp" >"$SERVER/cache/x"

cd "$TMP"
"$GE" init "$SERVER" site --exclude '/cache/**' >/dev/null 2>&1
check "init creates local copy" test -f site/index.php
check "init writes history next to the server dir" test -f "$SERVER.git-everywhere/HEAD"
check "history is protected by .htaccess" grep -q "Require all denied" "$SERVER.git-everywhere/.htaccess"
check "local config does not go to the server" test ! -e "$SERVER.git-everywhere/config"
same "initial commit" 1 "$(git -C site rev-list --count HEAD)"
first=$(git -C site rev-parse HEAD)

cd site
check "excluded files are not versioned" test -z "$(git ls-files cache)"
echo "<?php echo 'v2';" >"$SERVER/index.php"
echo "new" >"$SERVER/sub/new.txt"
rm "$SERVER/sub/page.html"
touch -t 202001010000 "$SERVER/index.php" # changed content, but force a different mtime anyway

status=$("$GE" status 2>/dev/null)
check "status shows changed file" grep -q "^~ index.php" <<<"$status"
check "status shows new file" grep -q "^+ sub/new.txt" <<<"$status"
check "status shows deleted file" grep -q "^- sub/page.html" <<<"$status"
check "status ignores excluded files" test -z "$(grep cache <<<"$status" || true)"

"$GE" snapshot -m "second" >/dev/null 2>&1
same "snapshot commits" 2 "$(git rev-list --count HEAD)"
same "snapshot message" "second" "$(git log -1 --format=%s)"
"$GE" snapshot >/dev/null 2>&1
same "no empty commits" 2 "$(git rev-list --count HEAD)"

# Restore the first state on the server
"$GE" restore "$first" --yes >/dev/null 2>&1
same "restore brings back old content" "<?php echo 'v1';" "$(cat "$SERVER/index.php")"
check "restore brings back deleted file" test -f "$SERVER/sub/page.html"
check "restore removes newer file" test ! -e "$SERVER/sub/new.txt"
check "restore leaves excluded files alone" test -f "$SERVER/cache/x"
same "restore is recorded as a commit" "Restore ${first:0:7}" "$(git log -1 --format=%s)"
cd ..

# A second machine picks up the existing history
"$GE" init "$SERVER" second >/dev/null 2>&1
same "second copy sees the whole history" "$(git -C site rev-parse HEAD)" "$(git -C second rev-parse HEAD)"
check "second copy has a clean work tree" test -z "$(git -C second status --porcelain)"

# The first copy is now behind if the second one commits
echo "from second" >"$SERVER/second.txt"
(cd second && "$GE" snapshot >/dev/null 2>&1)
echo "conflict" >"$SERVER/other.txt"
if (cd site && "$GE" snapshot >/dev/null 2>&1); then
	fail "outdated copy must refuse to snapshot"
else
	ok "outdated copy refuses to snapshot"
fi
(cd site && "$GE" fetch >/dev/null 2>&1 && "$GE" snapshot >/dev/null 2>&1)
same "after fetch the outdated copy can continue" "$(git -C site rev-list --count HEAD)" \
	"$(($(git -C second rev-list --count HEAD) + 1))"

echo
if [ "$FAILS" -eq 0 ]; then echo "all tests passed"; else echo "$FAILS test(s) failed"; exit 1; fi
