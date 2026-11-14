"""Собирает папку аддона RaidPartyLeader: ресурсы из res/, скрипты из lua/ в Windows-1251.

  python gen/assemble.py [папка аддона]     — по умолчанию out/RaidPartyLeader

Ресурсы (виджеты, тексты, текстуры, AddonDesc) лежат готовыми в res/RaidPartyLeader —
генератора ресурсов у RPL нет. В AddonDesc подставляется версия из lua/Util.lua (RPL.VERSION),
в Texts/AddonName.txt — имя с версией. Отладка вырезается (tools/strip_debug.py),
если сборка не отладочная (ALLODS_DEBUG=1).
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NAME = 'RaidPartyLeader'
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'out', NAME)
sys.path.insert(0, os.path.join(ROOT, '..', '..', 'tools'))
import strip_debug  # noqa: E402

SCRIPTS = ['LibDnD', 'Util', 'Storage', 'Game', 'View', 'Main']
VERSION = re.search(r'RPL\.VERSION = "([^"]+)"', open(os.path.join(ROOT, 'lua', 'Util.lua'), encoding='utf-8').read()).group(1)

shutil.rmtree(OUT, ignore_errors=True)
shutil.copytree(os.path.join(ROOT, 'res', NAME), OUT)

sd = os.path.join(OUT, 'Scripts')
os.makedirs(sd, exist_ok=True)
for s in SCRIPTS:
    raw = open(os.path.join(ROOT, 'lua', s + '.lua'), 'rb').read()
    data = raw if s == 'LibDnD' else strip_debug.strip(raw.decode('utf-8'), where=s + '.lua').encode('cp1251')
    open(os.path.join(sd, s + '.lua'), 'wb').write(data)

desc_path = os.path.join(OUT, 'AddonDesc.(UIAddon).xdb')
desc = open(desc_path, encoding='utf-8').read()
desc, n = re.subn(r'<version>[^<]*</version>', '<version>%s</version>' % VERSION, desc)
assert n == 1, 'в AddonDesc нет <version>'
for s in SCRIPTS:
    assert 'Scripts/%s.lua' % s in desc, 'в AddonDesc нет Scripts/%s.lua' % s
open(desc_path, 'w', encoding='utf-8', newline='').write(desc)

# имя аддона в игре — всегда с версией
open(os.path.join(OUT, 'Texts', 'AddonName.txt'), 'wb').write(b'\xff\xfe' + ('%s v%s' % (NAME, VERSION)).encode('utf-16-le'))
print('version', VERSION, '| files:', sum(len(f) for _, _, f in os.walk(OUT)))
