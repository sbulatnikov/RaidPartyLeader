--------------------------------------------------------------------------------
-- RaidPartyLeader / Storage.lua
-- Сохранённые формирования в конфиге персонажа.
--
-- Запись формирования (класс и аспект НЕ сохраняются — они вычисляются в моменте):
-- {
--   id = 7, name = "Отряд #7", kind = "party" | "raid" | "small",
--   members = { { n = "Ник", g = 1, s = 1 }, ... },   -- g: группа 1..4, s: место 1..6
--   leader = "Ник", assist = { "Ник", ... }, loot = "Ник" | nil,
-- }
--
-- «Быстрое» — одна запись: data.quick = { ref = id } (ссылка на сохранённое) или
-- { snap = запись, at = "15.11 21:40" } (снимок по ПКМ). Снимок адресуется ключом
-- Store.QUICK вместо id: Store.Get( Store.QUICK ) отдаёт его как обычное формирование.
-- Связь «Текущего» (data.link) — id сохранённого или Store.QUICK.
--------------------------------------------------------------------------------
RPL.Store = {}
local Store = RPL.Store

local SECTION = "RaidPartyLeader"
local data = nil

Store.QUICK = "quick"

local function Save()
	if data then userMods.SetAvatarConfigSection( SECTION, data ) end
end

function Store.Load()
	local d = userMods.GetAvatarConfigSection( SECTION )
	-- Ожидаем: у нового персонажа секции ещё нет (nil) — начинаем с пустой
	data = type( d ) == "table" and d or {}
	data.version = data.version or 1
	data.nextId = data.nextId or 1
	data.list = data.list or {}
	data.autoRetry = nil -- автоповтора больше нет (до 0.9.8)
	data.classes = data.classes or {}
end

-- Общие настройки аддона — одни на всех персонажей: глобальная секция конфига
-- (Mods/Configs/RaidPartyLeader/user.cfg, блок global). Секция пишется целиком,
-- поэтому перед записью читаем её заново.
local function ReadGlobal()
	local g = userMods.GetGlobalConfigSection( common.GetAddonName() )
	-- Ожидаем: при первом запуске секции настроек нет (nil) — начинаем с пустой
	return type( g ) == "table" and g or {}
end

-- Уведомления включены, пока их не выключили колокольчиком в шапке окна
function Store.LoadGlobal()
	RPL.toasts = ReadGlobal().toasts ~= false
end

function Store.SetToasts( on )
	RPL.toasts = on and true or false
	local g = ReadGlobal()
	g.toasts = RPL.toasts
	userMods.SetGlobalConfigSection( common.GetAddonName(), g )
end

--@debug
-- Отладочная сборка: ключ debug=true|false в глобальной секции конфига
-- (Mods/Configs/RaidPartyLeader/user.cfg, блок global). Править файл при закрытой игре.
function Store.LoadSettings()
	local g = userMods.GetGlobalConfigSection( common.GetAddonName() )
	RPL.DEBUG = type( g ) == "table" and g.debug == true
end
--@end

-- Класс персонажа по нику: не меняется, поэтому хранится между сессиями
function Store.GetClass( name )
	return data and data.classes and data.classes[ name ] or nil
end

function Store.SetClass( name, classKey )
	if not data or not name or name == "" then return end
	if data.classes[ name ] ~= classKey then
		data.classes[ name ] = classKey
		Save()
	end
end

function Store.AutoName( kind, id )
	return RPL.F( kind == "party" and RPL.L.autoParty or RPL.L.autoRaid, id )
end

-- Новые сверху
function Store.List()
	local r = {}
	for i = #data.list, 1, -1 do r[ #r + 1 ] = data.list[ i ] end
	return r
end

function Store.Get( id )
	if not id or not data then return nil end
	if id == Store.QUICK then return data.quick and data.quick.snap or nil end
	for _, f in ipairs( data.list ) do
		if f.id == id then return f end
	end
end

function Store.Add( rec, name )
	local id = data.nextId
	data.nextId = id + 1
	rec.id = id
	name = RPL.Trim( name )
	rec.name = ( name ~= "" ) and name or Store.AutoName( rec.kind, id )
	table.insert( data.list, rec )
	Save()
	return id
end

function Store.Update( id, rec )
	local f = Store.Get( id )
	if not f then return false end
	f.kind = rec.kind
	f.members = rec.members
	f.leader = rec.leader
	f.assist = rec.assist
	f.loot = rec.loot
	f.lootScheme = rec.lootScheme
	f.lootQuality = rec.lootQuality
	Save()
	return true
end

-- Дележ и ценность сохранённого формирования (правка из карточки)
function Store.SetLoot( id, scheme, quality )
	local f = Store.Get( id )
	if not f then return false end
	f.lootScheme, f.lootQuality = scheme, quality
	Save()
	return true
end

-- Занято ли название (без учёта регистра); exceptId — само переименовываемое формирование
function Store.NameTaken( name, exceptId )
	local n = RPL.Lower( RPL.Trim( name ) )
	if n == "" then return false end
	for _, f in ipairs( data.list ) do
		if f.id ~= exceptId and RPL.Lower( f.name ) == n then return true end
	end
	return false
end

function Store.Rename( id, name )
	local f = Store.Get( id )
	if not f then return false end
	name = RPL.Trim( name )
	f.name = ( name ~= "" ) and name or Store.AutoName( f.kind, f.id )
	Save()
	return true
end

function Store.Delete( id )
	for i, f in ipairs( data.list ) do
		if f.id == id then
			table.remove( data.list, i )
			-- «Быстрое» ссылалось на него — теперь пусто
			if data.quick and data.quick.ref == id then data.quick = nil end
			Save()
			return f
		end
	end
end

-- Связь «текущий состав <-> сохранённое» переживает перезаход
function Store.GetLink()
	return data and data.link or nil
end

function Store.SetLink( id )
	if not data or data.link == id then return end
	data.link = id
	Save()
end

function Store.NextId()
	return data and data.nextId or 1
end

--------------------------------------------------------------------------------
-- «Быстрое»
--------------------------------------------------------------------------------
-- Ключ формирования из «Быстрого» (id сохранённого или Store.QUICK) или nil, если пусто.
-- Ссылка на удалённое сохранённое считается пустой.
function Store.QuickKey()
	local q = data and data.quick
	if not q then return nil end
	if q.snap then return Store.QUICK end
	if q.ref and Store.Get( q.ref ) then return q.ref end
	return nil
end

function Store.QuickIsSnap()
	return data and data.quick and data.quick.snap ~= nil or false
end

function Store.QuickAt()
	return data and data.quick and data.quick.at or ""
end

function Store.SetQuickRef( id )
	data.quick = { ref = id }
	Save()
end

function Store.SetQuickSnap( rec, name )
	rec.id = Store.QUICK
	rec.name = name
	data.quick = { snap = rec, at = RPL.Stamp() }
	Save()
end

function Store.ClearQuick()
	data.quick = nil
	Save()
end
