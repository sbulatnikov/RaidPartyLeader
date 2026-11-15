#!/bin/sh
# Тесты RaidPartyLeader на заглушках API игры: обычная сборка скриптов (без отладки) и отладочная
#   sh test/run.sh [папка для временных файлов]      по умолчанию out/test
# Нужны Python 3 и texlua, luajit или lua5.1 (LUA=<путь> — указать свой интерпретатор, PYTHON=<путь> — свой Python).
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=${1:-$HERE/out/test}
PY=${PYTHON:-}
if [ -z "$PY" ]; then
	for c in python3 python; do
		if "$c" -c "import sys; sys.exit(sys.version_info[0] != 3)" 2>/dev/null; then PY=$c; break; fi
	done
fi
[ -n "$PY" ] || { echo "не найден Python 3 (можно указать PYTHON=<путь>)"; exit 1; }
if [ -z "$LUA" ]; then
	for c in texlua luajit lua5.1; do
		if command -v "$c" >/dev/null 2>&1; then LUA=$c; break; fi
	done
fi
[ -n "$LUA" ] || { echo "не найден texlua, luajit или lua5.1 (можно указать LUA=<путь>)"; exit 1; }
rm -rf "$TMP"; mkdir -p "$TMP/release" "$TMP/debug"
ALLODS_DEBUG=0 "$PY" "$HERE/tools/strip_debug.py" "$HERE/lua" "$TMP/release"
ALLODS_DEBUG=1 "$PY" "$HERE/tools/strip_debug.py" "$HERE/lua" "$TMP/debug"
for kind in release debug; do
	echo "== сборка: $kind"
	# при ошибке показываем конец журнала прогона и останавливаемся
	"$LUA" "$HERE/test/run.lua" "$HERE" "$TMP/$kind" > "$TMP/$kind.log" 2>&1 || { tail -30 "$TMP/$kind.log"; exit 1; }
	tail -1 "$TMP/$kind.log"
done
