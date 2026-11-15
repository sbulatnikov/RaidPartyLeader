--------------------------------------------------------------------------------
-- RaidPartyLeader / Util.lua
-- Общие помощники: строки, тексты интерфейса, доступ к виджетам и текстурам.
-- Файл в кодировке Windows-1251, как и остальные скрипты аддона.
--------------------------------------------------------------------------------
Global( "RPL", {} )

RPL.VERSION = "0.11.0"
RPL.tick = 0                 -- счётчик секунд (EVENT_SECOND_TIMER)
RPL.GROUP_SIZE = 6
RPL.UI_SCALE = 1.2          -- масштаб интерфейса; должен совпадать с RPL_SCALE генератора

-- Размер из макета (в пикселях прототипа) в пиксели окна — так же, как округляет генератор
function RPL.Px( v )
	return math.floor( v * RPL.UI_SCALE + 0.5 )
end
RPL.NICK_MIN = 3
RPL.NICK_MAX = 14
RPL.NAME_MAX = 40            -- длина названия формирования
RPL.TOAST_TIME = 8          -- секунд; пока тост тащат, он не исчезает
RPL.DEBUG = false           -- отладка в чат; включается в конфиге: debug=true (см. Storage.LoadSettings) --@debug

--------------------------------------------------------------------------------
-- Тексты
--------------------------------------------------------------------------------
RPL.L = {
	kindParty = "Группа",
	kindRaid = "Отряд",
	kindSmall = "Малый отряд",
	kindNone = "Без группы",
	kindNoneAsm = "Без группы · идёт сбор",
	kindShort = { party = "Группа", small = "Малый", raid = "Отряд" },
	kindIn = { party = "группе", small = "малом отряде", raid = "отряде" },
	kindTo = { party = "группу", small = "малый отряд", raid = "отряд" },
	autoParty = "Группа #%d",
	autoRaid = "Отряд #%d",
	groupTitle = "Группа %d",
	modeChip = "%s · %d/%d",
	saveParty = "Сохранить группу",
	saveRaid = "Сохранить отряд",
	currentParty = "Текущая группа",
	currentRaid = "Текущий отряд",
	notSaved = "Не сохранено",
	linkItem = "%s · %s/%s",
	linkCurrent = " (текущее)",
	linkUnlink = "Отвязать от сохранённого",
	linkCancel = "Отменить сбор",
	linkNoGroup = "Вы не в группе",
	linkNone = "Сохранённых формирований нет",
	linkDone = "Связано с «%s»",
	linkUnlinked = "Связь с сохранённым снята",
	linkQuick = "Не сохранено · %s",
	quickName = "%s %d · %s",
	quickMetaSnap = "Снимок по ПКМ · не сохранён · %d участн.",
	quickMetaRef = "Из «Сохранённых» · %d участн.",
	toastQuickSnap = "Снимок в «Быстрое»: %s",
	toastQuickRef = "В «Быстрое»: %s",
	toastQuickDeleted = "Снимок удалён",
	toastQuickBusy = "Идёт сбор снимка — он не заменён. Чтобы запомнить новый состав, сначала отвяжите его скрепкой.",
	toastQuickRemoved = "Убрано из «Быстрого» (в «Сохранённых» осталось)",
	toastForeignInvite = "Вы вступили в чужое формирование — сбор отменён",
	noteOther = "Вы сейчас в «%s». Чтобы собирать это, выйдите из него или выберите это формирование скрепкой в «Текущем».",
	noteUnknown = "Вы в группе, которая ни с чем не связана. Выберите это формирование скрепкой в «Текущем» или выйдите из группы.",
	noteKind = "Вы в %s — его нельзя превратить в %s. Выйдите из него, чтобы собрать это.",
	diffPrefix = "Изменено: ",
	diffMissing = "нет %d",
	diffAdded = "не из состава %d",
	diffOverflow = "не помещаются: %s",
	diffRoles = "роли",
	diffLoot = "дележ",
	diffQuality = "ценность",
	nameTaken = "Такое название уже есть — выберите другое",
	diffKind = "тип",
	inviteAll = "Пригласить всех · %d",
	placeAll = "     Расставить · %d",
	members = "%d участн.",
	dlgSaveParty = "Сохранить группу",
	dlgSaveRaid = "Сохранить отряд",
	dlgRename = "Переименовать",
	dlgSaveQuick = "Сохранить снимок",
	dlgHint = "Если оставить пустым — «%s»",
	toastSaved = "Сохранено: %s",
	toastUpdated = "Обновлено: %s",
	toastRenamed = "Переименовано: %s",
	toastDeleted = "Удалено: %s",
	toastInvited = "Приглашение отправлено: %s",
	toastNick = "Ник — от 3 до 14 символов",
	toastFull = "Группа %d заполнена",
	toastSkip = "Группы идут по порядку: сначала нужен игрок в группе %d",
	toastAlone = "%s — последний в группе %d: дальше перенести нельзя, группы сдвинутся",
	toastLootLeader = "Добычу распределяет лидер",
	toastNotLeader = "Нужны права лидера или помощника",
	toastOnlyLeader = "Только лидер может назначать помощника и ответственного за добычу и исключать из отряда",
	toastAssembled = "Формирование собрано",
	toastAssembledPlace = "Формирование собрано — расставляю по местам",
	toastPlaced = "Все на своих местах",
	toastForeign = "%s. Игроки с других серверов и из других фракций не сохранены: %s",
	toastReadyBusy = "Проверка готовности уже идёт",
	toastLeaderConfirm = "Нажмите ещё раз, чтобы передать лидерство: %s",
	toastLeaderOffline = "%s не в сети — лидерство передать нельзя",
	toastReadyRights = "Проверку готовности запускают лидер и помощники",
	toastReadyAll = "Готовы все: %s",
	toastReadyNot = "Не готовы: %s",
	toastReadyWait = "Не ответили: %s",
	noteNotLeader = "Приглашать может только лидер",
	aspectWord = "Аспект",
	aspectNames = {
		TANK = "Защит",
		HEAL = "Исцел",
		SUPPORT = "Поддерж",
		DAMAGE = "Нападен",
	},
}

--------------------------------------------------------------------------------
-- Дележ добычи и минимальная ценность (как в меню игры).
-- В конфиге храним ключи-строки, а не числа enum: числа могут смениться с версией клиента.
--------------------------------------------------------------------------------
RPL.SCHEMES = {
	{ key = "FREE_FOR_ALL", label = "Бери кто хочет", enum = LOOT_SCHEME_TYPE_FREE_FOR_ALL },
	{ key = "GROUP", label = "Кому повезёт", enum = LOOT_SCHEME_TYPE_GROUP },
	{ key = "MASTER", label = "Заведующий добычей", enum = LOOT_SCHEME_TYPE_MASTER },
}
RPL.QUALITIES = {
	{ key = "JUNK", label = "Хлам", enum = ITEM_QUALITY_JUNK },
	{ key = "GOODS", label = "Обычные", enum = ITEM_QUALITY_GOODS },
	{ key = "COMMON", label = "Добротные", enum = ITEM_QUALITY_COMMON },
	{ key = "UNCOMMON", label = "Замечательные", enum = ITEM_QUALITY_UNCOMMON },
	{ key = "RARE", label = "Редкие", enum = ITEM_QUALITY_RARE },
	{ key = "EPIC", label = "Легендарные", enum = ITEM_QUALITY_EPIC },
	{ key = "LEGENDARY", label = "Чудесные", enum = ITEM_QUALITY_LEGENDARY },
	{ key = "RELIC", label = "Реликвии", enum = ITEM_QUALITY_RELIC },
}

local function FindBy( list, field, value )
	if value == nil then return nil end
	for _, it in ipairs( list ) do
		if it[ field ] == value then return it end
	end
end

function RPL.Scheme( key ) return FindBy( RPL.SCHEMES, "key", key ) end
function RPL.SchemeByEnum( v ) return FindBy( RPL.SCHEMES, "enum", v ) end
function RPL.Quality( key ) return FindBy( RPL.QUALITIES, "key", key ) end
function RPL.QualityByEnum( v ) return FindBy( RPL.QUALITIES, "enum", v ) end

--------------------------------------------------------------------------------
-- Строки
--------------------------------------------------------------------------------
function RPL.WS( s )
	return userMods.ToWString( s or "" )
end

-- Обычная строка из string или WString
function RPL.S( v )
	if type( v ) == "string" then return v end
	-- Ожидаем: на входе может быть не строка (nil, число, другой объект API) — тогда пустая строка
	if v ~= nil and apitype( v ) == "WString" then return userMods.FromWString( v ) end
	return ""
end

-- Нижний регистр для Windows-1251 (string.lower знает только латиницу)
function RPL.Lower( s )
	return ( string.gsub( s or "", ".", function( c )
		local b = string.byte( c )
		if ( b >= 65 and b <= 90 ) or ( b >= 0xC0 and b <= 0xDF ) then return string.char( b + 32 ) end
		if b == 0xA8 then return string.char( 0xB8 ) end -- Ё
		return c
	end ) )
end

function RPL.Trim( s )
	return ( string.gsub( s or "", "^%s*(.-)%s*$", "%1" ) )
end

-- Длина в символах. Если строка — корректный UTF-8 с многобайтными символами,
-- считаем символы UTF-8, иначе байты (Windows-1251).
function RPL.CharLen( s )
	s = s or ""
	local n, i, len = 0, 1, #s
	while i <= len do
		local c = string.byte( s, i )
		local k = ( c < 0x80 and 1 ) or ( c >= 0xC2 and c <= 0xDF and 2 ) or ( c >= 0xE0 and c <= 0xEF and 3 ) or ( c >= 0xF0 and c <= 0xF4 and 4 ) or 0
		if k == 0 or i + k - 1 > len then return len end
		for j = i + 1, i + k - 1 do
			local b = string.byte( s, j )
			if b < 0x80 or b > 0xBF then return len end
		end
		n = n + 1
		i = i + k
	end
	return n
end

function RPL.ValidNick( s )
	local n = RPL.CharLen( s )
	return n >= RPL.NICK_MIN and n <= RPL.NICK_MAX
end

function RPL.F( fmt, ... )
	return string.format( fmt, ... )
end

-- Сообщение в чат: «Системные -> Дополнения». level: message | notice | warning | error
function RPL.Chat( text, level )
	userMods.SendSelfChatMessage( RPL.WS( "[RPL] " .. tostring( text ) ), level or "message" )
end

local function Join( ... )
	local parts = {}
	for i = 1, select( "#", ... ) do
		local v = ( select( i, ... ) )
		local s = RPL.S( v )
		if s == "" and type( v ) ~= "string" then s = tostring( v ) end
		parts[ #parts + 1 ] = s
	end
	return table.concat( parts, " " )
end

--@debug
-- Отладочная сборка: сообщения в чат при RPL.DEBUG (в обычной сборке этого блока нет)
function RPL.Log( ... )
	if RPL.DEBUG then RPL.Chat( Join( ... ), "message" ) end
end
--@end

function RPL.Warn( ... )
	RPL.Chat( Join( ... ), "warning" )
end

function RPL.Copy( t )
	if type( t ) ~= "table" then return t end
	local r = {}
	for k, v in pairs( t ) do r[ k ] = RPL.Copy( v ) end
	return r
end

function RPL.Set( list )
	local r = {}
	for _, v in ipairs( list or {} ) do r[ v ] = true end
	return r
end

function RPL.KindLabel( kind )
	if kind == "party" then return RPL.L.kindParty end
	if kind == "raid" then return RPL.L.kindRaid end
	if kind == "small" then return RPL.L.kindSmall end
	return RPL.L.kindNone
end

function RPL.KindGroups( kind )
	if kind == "raid" then return 4 end
	if kind == "small" then return 2 end
	if kind == "party" then return 1 end
	return 0
end

function RPL.IsRaidKind( kind )
	return kind == "raid" or kind == "small"
end

-- В игре есть только переход «группа -> малый отряд / отряд». Малый отряд и отряд друг
-- в друга не превращаются, отряд в группу — тоже: собрать f в таком составе нельзя.
function RPL.KindBlocked( stKind, fKind )
	return stKind ~= "none" and stKind ~= "party" and stKind ~= fKind
end

-- «15.11 21:40» — время снимка по часам компьютера
function RPL.Stamp()
	local d = common.GetLocalDateTime()
	return string.format( "%02d.%02d %02d:%02d", d.d, d.m, d.h, d.min )
end

-- Зажат ли Shift при нажатии (params.kbFlags реакции, флаги KBF_...)
function RPL.Shift( params )
	local f = params and params.kbFlags
	if type( f ) ~= "number" then return false end
	return math.floor( f / KBF_SHIFT ) % 2 == 1
end

--------------------------------------------------------------------------------
-- Виджеты
--------------------------------------------------------------------------------
local widgetCache = {}

-- Виджет с уникальным именем во всём дереве формы.
function RPL.W( name )
	local w = widgetCache[ name ]
	if w == nil then
		w = mainForm:GetChildChecked( name, true ) or false
		widgetCache[ name ] = w
	end
	return w or nil
end

function RPL.Child( parent, name )
	if not parent then return nil end
	return parent:GetChildChecked( name, false )
end

-- Последние выставленные значения: повторный вызов с тем же значением
-- не трогает движок (окно обновляется каждую секунду).
-- Виджеты — индексируемые userdata, как ключи таблицы работают по значению.
local memo = setmetatable( {}, { __mode = "k" } )
local function M( w )
	local m = memo[ w ]
	if not m then m = {} memo[ w ] = m end
	return m
end

function RPL.Forget( w )
	if w then memo[ w ] = nil end
end

function RPL.Show( w, on )
	if not w then return end
	on = on and true or false
	local m = M( w )
	if m.show ~= on then m.show = on w:Show( on ) end
end

function RPL.Enable( w, on )
	if not w then return end
	on = on and true or false
	local m = M( w )
	if m.enable ~= on then m.enable = on w:Enable( on ) end
end

-- Прозрачность виджета вместе с детьми (для составных кнопок, у которых
-- подпись и значок — отдельные дочерние виджеты и не тускнеют при Enable(false))
function RPL.Fade( w, a )
	if not w then return end
	local m = M( w )
	if m.fade ~= a then m.fade = a w:SetFade( a ) end
end

-- TextView с подстановкой <r name="value"/>
function RPL.SetText( w, s )
	if not w then return end
	s = s or ""
	local m = M( w )
	if m.text ~= s then m.text = s w:SetVal( "value", RPL.WS( s ) ) end
end

-- Кнопка с TextTag button_label
function RPL.SetLabel( w, s )
	if not w then return end
	s = s or ""
	local m = M( w )
	if m.label ~= s then m.label = s w:SetVal( "button_label", RPL.WS( s ) ) end
end

function RPL.SetVariant( w, v )
	if not w then return end
	local m = M( w )
	if m.variant ~= v then m.variant = v w:SetVariant( v ) end
end

--------------------------------------------------------------------------------
-- Текстуры (группы из texturesGroups в AddonDesc)
--------------------------------------------------------------------------------
local texGroups = {}
local texCache = {}

function RPL.Tex( group, key )
	if not key then return nil end
	local cacheKey = group .. ":" .. key
	local t = texCache[ cacheKey ]
	if t ~= nil then return t or nil end
	local g = texGroups[ group ]
	if g == nil then
		g = common.GetAddonRelatedTextureGroup( group, true ) or false
		texGroups[ group ] = g
	end
	t = false
	if g and g:HasTexture( key ) then t = g:GetTexture( key ) end
	texCache[ cacheKey ] = t
	return t or nil
end

function RPL.SetTex( w, group, key )
	local t = RPL.Tex( group, key )
	if w and t then
		local m = M( w )
		local id = group .. ":" .. key
		if m.tex ~= id then m.tex = id w:SetBackgroundTexture( t ) end
	end
	return t ~= nil
end

--------------------------------------------------------------------------------
-- Тост
--------------------------------------------------------------------------------
RPL.toastLeft = 0

function RPL.Toast( text )
	RPL.SetText( RPL.W( "ToastText" ), text )
	RPL.Show( RPL.W( "Toast" ), true )
	RPL.toastLeft = RPL.TOAST_TIME
end

function RPL.ToastTick()
	local id = DnD and DnD.Dragging
	local w = id and DnD.Widgets and DnD.Widgets[ id ]
	if w and w.wtMovable:GetName() == "Toast" then return end -- тащат: не прячем
	if RPL.toastLeft > 0 then
		RPL.toastLeft = RPL.toastLeft - 1
		if RPL.toastLeft <= 0 then RPL.Show( RPL.W( "Toast" ), false ) end
	end
end
