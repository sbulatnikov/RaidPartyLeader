RaidPartyLeader — исходники
===========================
lua/   скрипты в UTF-8 (при сборке переводятся в Windows-1251; LibDnD — как есть)
res/   готовые ресурсы аддона: AddonDesc, виджеты, тексты, текстуры (генератора ресурсов нет)
gen/   assemble.py — собирает папку аддона из res/ и lua/, подставляет версию из RPL.VERSION
addon/ последняя сборка — то, что попадает в .pak

Сборка и установка: python tools\build.py RaidPartyLeader  (из C:\Development\Allods)
Отладочная сборка:  python tools\build.py RaidPartyLeader --debug
