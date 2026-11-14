#!/bin/sh
# Тесты RaidPartyLeader: обычная сборка (без отладки) и отладочная
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/rpl-test
rm -rf "$TMP"; mkdir -p "$TMP/release" "$TMP/debug"
python3 "$HERE/../../tools/strip_debug.py" "$HERE/lua" "$TMP/release"
ALLODS_DEBUG=1 python3 "$HERE/../../tools/strip_debug.py" "$HERE/lua" "$TMP/debug"
echo "== обычная сборка"; texlua "$HERE/test/run.lua" "$HERE" "$TMP/release" | grep -E "FAIL|ВСЁ|ИТОГ|ошиб|error" | tail -8
echo "== отладочная сборка"; texlua "$HERE/test/run.lua" "$HERE" "$TMP/debug" | grep -E "FAIL|ВСЁ|ИТОГ|ошиб|error" | tail -8
