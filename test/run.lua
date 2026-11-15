-- Прогон логики RaidPartyLeader на заглушках:
--   texlua test/run.lua <папка проекта> <папка скриптов>      (запускает test/run.sh)
-- Скрипты — lua/, пропущенные через tools/strip_debug.py (обычная или отладочная сборка).
local ROOT = arg and arg[ 1 ] or "."
local L = ( arg and arg[ 2 ] or ( ROOT .. "/lua" ) ) .. "/"
dofile( ROOT .. "/test/mock.lua" )

-- Сохранённые формирования (как их пишет аддон: участники по группам и местам)
local function F( id, name, kind, groups, assist, lootN, scheme, quality )
	local m = {}
	for g, grp in ipairs( groups ) do for s, n in ipairs( grp ) do m[ #m + 1 ] = { n = n, g = g, s = s } end end
	return { id = id, name = name, kind = kind, members = m, leader = ME, assist = assist, loot = lootN, lootScheme = scheme, lootQuality = quality }
end
G24 = {
	{ ME, "Вельмира", "Ксаэль", "Лиорана", "Сайрен", "Эйлин" },
	{ "Торбьорн", "Иссандра", "Мракобес", "Тиаль", "Гримтус", "Кельтар" },
	{ "Нордрик", "Сельвия", "Миракс", "Ферония", "Ольвейн", "Ракшас" },
	{ "Бурелом", "Злата", "Каэлум", "Хаггард", "Ярена", "Дорн" },
}
G12 = { { ME, "Вельмира", "Ксаэль", "Лиорана", "Сайрен", "Эйлин" }, { "Торбьорн", "Мракобес", "Тиаль", "Гримтус", "Кельтар", "Иссандра" } }
CONFIG.RaidPartyLeader = { version = 1, nextId = 4, classes = {}, autoRetry = true, list = {
	F( 1, "Вечерний рейд", "raid", G24, { "Вельмира", "Торбьорн" }, "Нордрик", "MASTER", "RARE" ),
	F( 2, "Статик", "small", G12, { "Вельмира" }, "Эйлин", "GROUP", "EPIC" ),
	F( 3, "Пати", "party", { { ME, "Ксаэль", "Сельвия", "Тиаль", "Ферония", "Дорн" } }, {}, nil, "FREE_FOR_ALL", "COMMON" ),
} }

for _, f in ipairs( { "LibDnD", "Util", "Storage", "Game", "View", "Main" } ) do dofile( L .. f .. ".lua" ) end

local fails = 0
local function check( cond, what )
	if cond then print( "OK   " .. what ) else print( "FAIL " .. what ) fails = fails + 1 end
end
local nlog = 0
local function second( n )
	for _ = 1, n or 1 do
		NOW = NOW + 1000
		EVENTS.EVENT_SECOND_TIMER( {} )
		-- сервер ответил на операцию с отрядом — событие изменения (как в игре)
		if #LOG > nlog then nlog = #LOG NOW = NOW + 400 EVENTS.EVENT_RAID_CHANGED( {} ) end
	end
end
local function react( r, w, extra )
	local p = { widget = FIND( w or "RPLButton" ), sender = w or "RPLButton" }
	for k, v in pairs( extra or {} ) do p[ k ] = v end
	REACTIONS[ r ]( p )
end
local function rmb( shift ) react( "rpl_rmb", "RPLButton", { kbFlags = shift and KBF_SHIFT or KBF_NONE } ) end
local function invited() local t = {} for _, i in ipairs( INVITES ) do t[ #t + 1 ] = i.to end return t end
local function has( list, x ) for _, v in ipairs( list ) do if v == x then return true end end return false end
local function toast() return TEXT( "ToastText" ) end
local function same( a, b ) -- составы групп совпадают поимённо и по местам
	if #a ~= #b then return false end
	for g = 1, #a do
		if #a[ g ] ~= #b[ g ] then return false end
		for s = 1, #a[ g ] do if a[ g ][ s ] ~= b[ g ][ s ] then return false end end
	end
	return true
end
local Store = RPL.Store

-- 1. Старт: вне группы, связи нет, автоповтор вычищен из конфига
react( "rpl_toggle" ) second()
check( RPL.link == nil and RPL.tab == "current", "старт: без связи" )
check( CONFIG.RaidPartyLeader.autoRetry == nil, "старт: ключ autoRetry убран" )
check( FIND( "EmptyView" ).visible, "старт: «Вы не в группе»" )
check( RPL.VERSION == "0.11.0", "версия 0.11.0" )

-- 2. Неизвестный состав: ровно как в сохранённом «Пати», но связи нет — угадывания больше нет
SET( "party", { { ME, "Ксаэль", "Сельвия", "Тиаль", "Ферония", "Дорн" } } )
second( 3 )
check( RPL.link == nil, "неизвестный: не связывается сам, даже при полном совпадении" )
check( TEXT( "LinkTitle" ) == "Текущая группа" and FIND( "SaveButton" ).visible, "неизвестный: «Текущая группа» и «Сохранить»" )
INVITES = {}
rmb( true ) second()
check( #INVITES == 0, "неизвестный: Shift+ПКМ ничего не делает" )
RPL.detailId = 1 react( "rpl_tab_saved" ) RPL.tab = "detail" RPL.Refresh()
check( not FIND( "StartInviteButton" ).enabled and string.find( TEXT( "InviteNote" ), "ни с чем не связана", 1, true ), "карточка: «Пригласить всех» неактивна в неизвестном составе" )
react( "rpl_start_invite", "StartInviteButton" ) second()
check( #INVITES == 0 and RPL.link == nil, "карточка: нажатие ничего не делает" )
react( "rpl_tab_current" )

-- 3. ПКМ в неизвестном: снимок в «Быстрое», «Текущее» связано с ним
rmb( false ) second()
check( RPL.link == Store.QUICK and Store.QuickIsSnap(), "ПКМ: снимок, связь со снимком" )
check( Store.Get( Store.QUICK ).name == "Группа 6 · 15.11 21:40", "ПКМ: имя снимка «" .. tostring( Store.Get( Store.QUICK ).name ) .. "»" )
check( string.find( toast(), "Снимок в «Быстрое»", 1, true ), "ПКМ: тост" )
check( string.find( TEXT( "LinkTitle" ), "Не сохранено · Группа 6", 1, true ) and FIND( "SaveButton" ).visible, "«Текущее»: «Не сохранено · …» и «Сохранить»" )
-- снимок -> «Сохранённые»: «Быстрое» и связь переходят на сохранённое
react( "rpl_tab_quick" )
check( FIND( "QuickSaveButton" ).visible and FIND( "QuickDeleteButton" ).visible and not FIND( "BackButton" ).visible, "«Быстрое»: у снимка «Сохранить» и «Удалить»" )
react( "rpl_quick_save", "QuickSaveButton" )
FIND( "NameEdit" ).text = "Пати-2"
react( "rpl_dialog_ok", "ConfirmButton" )
check( Store.Get( 4 ) and Store.Get( 4 ).name == "Пати-2" and RPL.link == 4 and Store.QuickKey() == 4, "снимок сохранён: связь и «Быстрое» — на сохранённое" )
check( not FIND( "QuickSaveButton" ).visible, "«Быстрое»: у ссылки нет «Сохранить»" )
react( "rpl_quick_delete", "QuickDeleteButton" )
check( Store.QuickKey() == nil and Store.Get( 4 ) and RPL.link == 4, "«Быстрое»: ссылка убрана, сохранённое и связь на месте" )
react( "rpl_tab_current" )

-- 4. Выход из группы — связь сброшена (через 2 с), «Быстрое» не трогается
rmb( false ) -- в сохранённом: в «Быстрое» ссылка, снимка нет
check( Store.QuickKey() == 4 and not Store.QuickIsSnap() and RPL.link == 4, "ПКМ в сохранённом: ссылка, связь не тронута" )
LEAVE() second( 3 )
check( RPL.link == nil and Store.QuickKey() == 4, "вышли: связь сброшена, «Быстрое» осталось" )

-- 5. Shift+ПКМ вне группы: «Быстрое» = «Вечерний рейд» (отряд). Первый по местам ->
--    группа -> отряд -> один раз все остальные -> пришли все -> расстановка, роли, дележ
Store.SetQuickRef( 1 )
INVITES = {} LOG = {} nlog = 0
rmb( true ) second()
check( #INVITES == 1 and INVITES[ 1 ].to == "Вельмира" and RPL.link == 1, "Shift+ПКМ вне группы: позван первый по местам" )
check( TEXT( "ModeText" ) == "Без группы · идёт сбор", "шапка: «Без группы · идёт сбор»" )
second( 3 )
check( RPL.link == 1, "вне группы во время сбора связь держится" )
check( FIND( "CurrentView" ).visible and TEXT( "LinkTitle" ) == "Вечерний рейд", "«Текущее» во время сбора показывает, что собираем" )
ACCEPT( "Вельмира" ) second()
check( has( LOG, "create" ) and STATE.kind == "raid", "принял первый: группа стала отрядом" )
second( 2 )
local rest = invited()
check( #rest == 23 and INVITES[ 2 ].into == "raid", "отряд появился: один раз позваны остальные (" .. ( #rest - 1 ) .. ")" )
second( 3 )
check( #INVITES == 23, "без нажатий больше не зовёт" )
-- приходят все, кроме одного, вперемешку по группам
local order = { "Дорн", "Ярена", "Хаггард", "Каэлум", "Злата", "Бурелом", "Ракшас", "Ольвейн", "Ферония", "Миракс", "Сельвия",
	"Нордрик", "Кельтар", "Гримтус", "Тиаль", "Мракобес", "Иссандра", "Торбьорн", "Эйлин", "Сайрен", "Лиорана" }
for _, n in ipairs( order ) do ACCEPT( n ) end
second()
check( RPL.asm.active and string.find( TEXT( "LinkState" ), "нет 1", 1, true ), "не хватает одного — сбор идёт" )
INVITES = {}
rmb( true ) second()
check( #INVITES == 1 and INVITES[ 1 ].to == "Ксаэль", "Shift+ПКМ в своём: дозвал недостающего" )
ACCEPT( "Ксаэль" ) second( 40 )
check( same( STATE.groups, G24 ), "все пришли: расставлены по местам" )
check( STATE.helpers[ "Вельмира" ] and STATE.helpers[ "Торбьорн" ] and STATE.loot == "Нордрик", "роли выданы" )
check( STATE.scheme == LOOT_SCHEME_TYPE_MASTER and STATE.quality == ITEM_QUALITY_RARE, "дележ и ценность выставлены" )
-- перемешались — Shift+ПКМ приводит в готовность (без приглашений)
local g = STATE.groups g[ 1 ][ 2 ], g[ 3 ][ 4 ] = g[ 3 ][ 4 ], g[ 1 ][ 2 ]
STATE.helpers[ "Вельмира" ] = nil
INVITES = {}
rmb( true ) second( 30 )
check( #INVITES == 0 and same( STATE.groups, G24 ), "Shift+ПКМ: перемешанных расставил" )
check( STATE.helpers[ "Вельмира" ], "Shift+ПКМ: снятую руками роль выдал заново" )

-- 6. ПКМ в сохранённом не ломает его
Store.ClearQuick()
rmb( false )
check( RPL.link == 1 and Store.QuickKey() == 1 and not Store.QuickIsSnap(), "ПКМ в сохранённом: «Быстрое» = ссылка, связь та же" )

-- 7. Скрепка в чужом малом отряде: «Статик», в составе чужой — последние по местам не влезают
LEAVE() second( 3 )
SET( "small", { { ME, "Вельмира", "Ксаэль", "Лиорана", "Сайрен", "Эйлин" }, { "Торбьорн", "Мракобес", "Тиаль", "Чужак", "Кельтар" } } )
second()
check( RPL.link == nil, "чужой отряд: связи нет" )
RPL.link = 2 Store.SetLink( 2 ) RPL.Refresh() -- скрепка (как OnMenuPick)
check( string.find( TEXT( "LinkState" ), "не из состава 1", 1, true ) and string.find( TEXT( "LinkState" ), "не помещаются: Иссандра", 1, true ),
	"скрепка: «не из состава 1 · не помещаются: Иссандра» (" .. TEXT( "LinkState" ) .. ")" )
check( TEXT( "InviteAllButton" ) == "Пригласить всех · 1", "кнопка считает только тех, кто влезет" )
local stranger = RPL.st.byName[ "Чужак" ]
check( stranger and stranger.stranger, "Чужак помечен «не из состава»" )
INVITES = {}
rmb( true ) second()
check( #INVITES == 1 and INVITES[ 1 ].to == "Гримтус", "Shift+ПКМ: позвал только влезающего (Гримтус), Иссандра не влез" )

-- 8. Тип не совпадает: малый отряд не превратить в отряд
RPL.link = 1 Store.SetLink( 1 ) RPL.Refresh()
INVITES = {}
rmb( true ) second()
check( #INVITES == 0 and string.find( toast(), "малом отряде", 1, true ), "малый -> отряд: не собирает, объясняет" )

-- 9. Не лидер: Shift+ПКМ молчит
STATE.leader = "Вельмира" RPL.link = 2 Store.SetLink( 2 ) second()
INVITES = {} local t0 = toast()
rmb( true ) second()
check( #INVITES == 0, "не лидер: Shift+ПКМ ничего не делает" )

-- 10. Собирали вне группы, но вступили в чужое — сбор отменён
LEAVE() second( 3 )
Store.SetQuickRef( 1 )
INVITES = {}
rmb( true ) second()
check( #INVITES == 1 and RPL.asm and RPL.asm.active, "сбор вне группы начат" )
SET( "party", { { "Незнакомец", ME, "Ещёодин" } }, "Незнакомец" ) second()
check( RPL.link == nil and string.find( toast(), "чужое формирование", 1, true ), "вступили в чужое: сбор отменён" )

-- 11. Удалили сохранённое, на которое ссылалось «Быстрое» — «Быстрое» пусто
LEAVE() second( 3 )
Store.SetQuickRef( 3 )
Store.Delete( 3 )
react( "rpl_toggle" ) react( "rpl_toggle" ) react( "rpl_tab_quick" )
check( Store.QuickKey() == nil and FIND( "QuickEmptyView" ).visible, "удалили сохранённое: «Быстрое» пусто" )
INVITES = {}
rmb( true ) second()
check( #INVITES == 0, "пустое «Быстрое»: Shift+ПКМ ничего не делает" )

-- 12. Группа (не отряд) из снимка: вне группы зовёт всех сразу
SET( "party", { { ME, "Тарвин", "Ульма" } } ) second()
rmb( false )
LEAVE() second( 3 )
INVITES = {}
rmb( true ) second()
check( #INVITES == 2 and INVITES[ 1 ].into == "group", "снимок группы: вне группы позваны все" )

print( fails == 0 and "ВСЁ ОК" or ( "ИТОГ: ошибок " .. fails ) )
os.exit( fails == 0 and 0 or 1 )
