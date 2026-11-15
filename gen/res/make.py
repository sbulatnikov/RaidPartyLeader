"""Генератор ресурсов RaidPartyLeader (виджеты, тексты, текстуры, AddonDesc) -> ../../res/RaidPartyLeader.

  python gen/res/make.py

Скрипты (lua/) сюда не входят — их добавляет gen/assemble.py при сборке аддона.
Нужны Python 3 + Pillow. Иконки классов и аспектов берутся из ресурсов игры,
выгруженных в AddonUIBuilder/assets/Interface (или путь в RPL_ASSETS).
gen_a.py — текстуры, gen_b.py — общие виджеты, слоты, шапка, вкладки,
gen_c.py — экраны окна, диалог, тост, кнопка RPL, AddonDesc. Выполняются одним куском.
"""
import os, shutil, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
NAME = 'RaidPartyLeader'
assets = os.environ.get('RPL_ASSETS') or os.path.normpath(os.path.join(PROJ, '..', '..', 'AddonUIBuilder', 'assets', 'Interface'))
if not os.path.isdir(assets):
    sys.exit('нет ресурсов игры: %s (укажите RPL_ASSETS)' % assets)
tmp = tempfile.mkdtemp(prefix='rplres-')
try:
    out = os.path.join(tmp, NAME)
    os.environ.update(RPL_ROOT=out, RPL_ASSETS=assets, RPL_GEN=HERE)
    sys.path.insert(0, HERE)
    code = ''.join(open(os.path.join(HERE, f), encoding='utf-8').read() + '\n' for f in ('gen_a.py', 'gen_b.py', 'gen_c.py'))
    exec(compile(code, 'gen_abc', 'exec'), {'__name__': '__main__'})
    shutil.rmtree(os.path.join(out, 'Scripts'), ignore_errors=True)
    dst = os.path.join(PROJ, 'res', NAME)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(out, dst, dirs_exist_ok=True)  # если удалить не дали — перезаписываем поверх
    made = {os.path.relpath(os.path.join(b, f), out) for b, _, fs in os.walk(out) for f in fs}
    stale = sorted(os.path.relpath(os.path.join(b, f), dst) for b, _, fs in os.walk(dst) for f in fs
                   if os.path.relpath(os.path.join(b, f), dst) not in made)
    for f in stale:
        print('ВНИМАНИЕ: лишний файл в res, генератор его не создаёт:', f)
    print('ресурсы ->', os.path.relpath(dst, PROJ))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
