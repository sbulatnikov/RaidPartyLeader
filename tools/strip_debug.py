"""Вырезает отладку из скриптов аддона. Обычная и релизная сборка — без отладки.

Разметка в исходниках:
  --@debug        строка-начало блока
  ...             всё, что между ними, остаётся только в отладочной сборке
  --@end          строка-конец блока
  код --@debug    одиночная строка только для отладочной сборки

Вырезанные строки заменяются пустыми — номера строк в ошибках из mods.txt
совпадают с исходниками.
Отладочная сборка: переменная окружения ALLODS_DEBUG=1 (tools/build.py --debug).

  python strip_debug.py <папка .lua> <папка результата>   — для тестов на заглушках
"""
import os, re, sys

DEBUG = os.environ.get('ALLODS_DEBUG') == '1'
BEGIN = re.compile(r'^\s*--@debug\s*$')
END = re.compile(r'^\s*--@end\s*$')
LINE = re.compile(r'--@debug\s*$')


def strip(text, debug=None, where='?'):
    if debug is None:
        debug = DEBUG
    out, inside, start = [], False, 0
    for n, line in enumerate(text.split('\n'), 1):
        s = line.rstrip('\r')
        cr = '\r' if line.endswith('\r') else ''
        if BEGIN.match(s):
            if inside:
                raise ValueError('%s:%d: --@debug внутри блока с %d' % (where, n, start))
            inside, start = True, n
            out.append(cr)
        elif END.match(s):
            if not inside:
                raise ValueError('%s:%d: --@end без --@debug' % (where, n))
            inside = False
            out.append(cr)
        elif inside or LINE.search(s):
            out.append(line if debug else cr)
        else:
            out.append(line)
    if inside:
        raise ValueError('%s:%d: блок --@debug не закрыт' % (where, start))
    return '\n'.join(out)


if __name__ == '__main__':
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for n in sorted(os.listdir(src)):
        if n.endswith('.lua'):
            raw = open(os.path.join(src, n), 'rb').read()
            text = raw.decode('utf-8', 'surrogateescape')
            open(os.path.join(dst, n), 'wb').write(strip(text, where=n).encode('utf-8', 'surrogateescape'))
