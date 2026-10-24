#!/usr/bin/env bash
# Regression tests for bugs found in review, each with its own local "server".
# Usage: tests/regressions.sh   (needs git and rclone)
set -euo pipefail

GE=${GE:-"$(cd "$(dirname "$0")/.." && pwd)/git-everywhere"}
TMP=$(mktemp -d)
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# A global config with a content filter, like git-lfs installs one
printf '[filter "upper"]\n\tclean = tr a-z A-Z\n\tsmudge = cat\n' >"$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
FAILS=0

ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }
check() {
	local desc=$1; shift
	if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}
refuses() {
	local desc=$1; shift
	if "$@" >/dev/null 2>&1; then fail "$desc"; else ok "$desc"; fi
}
same() {
	local desc=$1 expected=$2 actual=$3
	if [ "$expected" = "$actual" ]; then ok "$desc"; else fail "$desc: expected '$expected', got '$actual'"; fi
}
ge() { "$GE" "$@" >/dev/null 2>&1; }
# Make a server folder with one file and a local copy of it in $TMP/<name>-copy
setup() {
	mkdir -p "$TMP/$1"
	echo "v1" >"$TMP/$1/index.php"
	(cd "$TMP" && ge init "$TMP/$1" "$1-copy" "${@:2}") || true
}

cd "$TMP"

# History inside the synced folder, written so that a plain string comparison misses it
setup srv1 --history "$TMP/./srv1/_hist"
first=$(git -C srv1-copy rev-parse HEAD)
echo "v2" >srv1/index.php
(cd srv1-copy && ge snapshot && ge restore "$first" --yes) || true
check "history inside the folder is not versioned" test -z "$(git -C srv1-copy ls-files _hist)"
same "restore does not delete bundles inside the folder" 3 "$(ls srv1/_hist/bundles | grep -c bundle)"

# --history must not contain the site
mkdir -p www/site1 && echo x >www/site1/a && echo y >www/neighbour
refuses "init refuses a history folder that contains the site" ge init "$TMP/www/site1" w1 --history "$TMP/www"
check "the site is still there" test -f www/neighbour

# uninstall only deletes its own files
setup srv2
echo "keep me" >srv2.git-everywhere/foreign.txt
(cd srv2-copy && ge uninstall --yes) || true
check "uninstall deletes the bundles" test ! -e srv2.git-everywhere/bundles
check "uninstall leaves other files in the history folder" test -f srv2.git-everywhere/foreign.txt

# Files matched by .gitignore on the server are versioned too
mkdir -p srv3/plugin/vendor
echo "vendor/" >srv3/plugin/.gitignore
echo "<?php" >srv3/plugin/vendor/lib.php
echo "secret" >srv3/.env
mkdir -p xdg/git && echo ".env" >xdg/git/ignore
(XDG_CONFIG_HOME="$TMP/xdg" ge init "$TMP/srv3" srv3-copy) || true
check "files ignored by .gitignore are versioned" test -n "$(git -C srv3-copy ls-files plugin/vendor/lib.php)"
check "files in the global ignore list are versioned" test -n "$(git -C srv3-copy ls-files .env)"

# Contents are stored byte for byte, whatever .gitattributes says
mkdir -p srv4
printf 'line1\r\nline2\r\n' >srv4/crlf.txt
printf '* text=auto\n*.bin filter=upper\n' >srv4/.gitattributes
printf 'binary data' >srv4/data.bin
ge init "$TMP/srv4" srv4-copy || true
check "CRLF is kept" cmp <(git -C srv4-copy cat-file -p HEAD:crlf.txt) srv4/crlf.txt
check "filters from .gitattributes are not applied" cmp <(git -C srv4-copy cat-file -p HEAD:data.bin) srv4/data.bin

# Git repositories on the server are versioned as plain files
setup srv5
git init -q srv5/plug && echo "code" >srv5/plug/file.php
git -C srv5/plug add -A && git -C srv5/plug -c user.name=t -c user.email=t@t commit -q -m x
(cd srv5-copy && ge snapshot) || true
check "files of a nested repository are versioned" test -n "$(git -C srv5-copy ls-files plug/file.php)"
same "no submodule entries" "" "$(git -C srv5-copy ls-files -s | grep '^160000' || true)"
check "the nested .git stays on the server" test -d srv5/plug/.git

# status and restore do not depend on rclone's log output
setup srv6
first=$(git -C srv6-copy rev-parse HEAD)
echo "v2 changed" >srv6/index.php
check "status works with RCLONE_FLAGS=-q" grep -q "^~ index.php" <<<"$(cd srv6-copy && RCLONE_FLAGS=-q "$GE" status 2>/dev/null)"
(cd srv6-copy && RCLONE_FLAGS=-q ge restore "$first" --yes) || true
same "restore works with RCLONE_FLAGS=-q" "v1" "$(cat srv6/index.php)"
check "nothing is left staged after restore" test -z "$(git -C srv6-copy status --porcelain)"

# Two bundles with the same number
setup srv7
echo "v2" >srv7/index.php
(cd srv7-copy && ge snapshot) || true
b=$(ls srv7.git-everywhere/bundles | grep '^000002-')
cp "srv7.git-everywhere/bundles/$b" "srv7.git-everywhere/bundles/000002-ffffffffffffffffffffffffffffffffffffffff.bundle"
refuses "snapshot refuses when two bundles have the same number" bash -c "cd '$TMP/srv7-copy' && '$GE' snapshot"
check "the message explains it" grep -q "same time" <<<"$(cd srv7-copy && "$GE" snapshot 2>&1 || true)"

# Another branch name in one copy does not break the others
setup srv8
git -C srv8-copy branch -m master
echo "v2" >srv8/index.php
(cd srv8-copy && ge snapshot) || true
ge init "$TMP/srv8" srv8-second || true
same "a copy on another branch can still be read" 2 "$(git -C srv8-second rev-list --count HEAD 2>/dev/null || echo 0)"

# sha256 as the user's default
mkdir -p srv9 && echo x >srv9/a
(GIT_DEFAULT_HASH=sha256 ge init "$TMP/srv9" srv9-copy) || true
same "copies always use sha1" sha1 "$(git -C srv9-copy rev-parse --show-object-format)"

# Relative local path
mkdir -p rel/srv10 && echo x >rel/srv10/a
(cd rel && ge init srv10 copy) || true
check "init with a relative path works" test -f rel/copy/a
same "the remote is stored as an absolute path" "$TMP/rel/srv10" "$(git -C rel/copy config everywhere.remote)"
refuses "a failed init leaves nothing behind" ge init "nope:" failed-copy
check "no half-made folder" test ! -e failed-copy

# Detached HEAD gives a clear message
setup srv11
echo "v2" >srv11/index.php
(cd srv11-copy && ge snapshot && git checkout -q HEAD~1) || true
check "detached HEAD is explained" grep -q "git checkout" <<<"$(cd srv11-copy && "$GE" status 2>&1 || true)"

# One unreadable file does not stop the snapshot of everything else
if [ "$(id -u)" != 0 ]; then
	setup srv12
	echo "v2" >srv12/index.php
	echo "locked" >srv12/locked.txt && chmod 000 srv12/locked.txt
	refuses "snapshot reports unreadable files" bash -c "cd '$TMP/srv12-copy' && '$GE' snapshot"
	same "the other changes are saved" "v2" "$(git -C srv12-copy show HEAD:index.php)"
	chmod 644 srv12/locked.txt
fi

# Filter changes are shared without a new commit
setup srv13
echo "- /logs/**" >>srv13-copy/.git/everywhere-filter
(cd srv13-copy && ge snapshot) || true
check "filter change is uploaded" grep -q logs srv13.git-everywhere/everywhere-filter

# Confirmation can come from stdin, and no temporary bundle stays behind
setup srv14
first=$(git -C srv14-copy rev-parse HEAD)
echo "v2" >srv14/index.php
(cd srv14-copy && echo n | ge restore "$first") || true
same "answering n keeps the server" "v2" "$(cat srv14/index.php)"
(cd srv14-copy && echo y | ge restore "$first") || true
same "answering y restores" "v1" "$(cat srv14/index.php)"
same "no partial uploads left" "" "$(ls srv14.git-everywhere/bundles | grep partial || true)"

echo
if [ "$FAILS" -eq 0 ]; then echo "all regression tests passed"; else echo "$FAILS regression test(s) failed"; exit 1; fi
