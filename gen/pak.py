"""Пакует собранный аддон в .pak — архив, который игра читает прямо из data\\Mods\\Addons.

  python3 gen/pak.py <папка аддона> <файл.pak>

.pak — обычный ZIP с путями  Mods/Addons/<имя аддона>/...  и записями для каждой папки
(так устроены все .pak в Addons). Записи помечаются
как созданные в MS-DOS/NTFS, сжатие deflate — как у архивов из 7-Zip.
"""
import os, sys, time, zipfile

ADDON = os.path.abspath(sys.argv[1])
PAK = os.path.abspath(sys.argv[2])
NAME = os.path.basename(ADDON)
ROOT = 'Mods/Addons/' + NAME
NOW = time.localtime()[:6]


def entry(name, is_dir):
    zi = zipfile.ZipInfo(name, NOW)
    zi.create_system = 0                      # MS-DOS / NTFS
    zi.external_attr = 0x10 if is_dir else 0x20
    zi.compress_type = zipfile.ZIP_STORED if is_dir else zipfile.ZIP_DEFLATED
    return zi


files = 0
with zipfile.ZipFile(PAK, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for d in ('Mods/', 'Mods/Addons/', ROOT + '/'):
        z.writestr(entry(d, True), b'')
    for base, dirs, names in os.walk(ADDON):
        dirs.sort()
        rel = os.path.relpath(base, ADDON).replace(os.sep, '/')
        prefix = ROOT + ('' if rel == '.' else '/' + rel)
        if rel != '.':
            z.writestr(entry(prefix + '/', True), b'')
        for n in sorted(names):
            z.writestr(entry(prefix + '/' + n, False), open(os.path.join(base, n), 'rb').read())
            files += 1

with zipfile.ZipFile(PAK) as z:
    bad = z.testzip()
    assert bad is None, bad
    assert ROOT + '/AddonDesc.(UIAddon).xdb' in z.namelist()
print('%s: файлов %d, записей %d, %d байт' % (os.path.basename(PAK), files, len(zipfile.ZipFile(PAK).namelist()), os.path.getsize(PAK)))
