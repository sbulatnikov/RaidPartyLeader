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
--------------------------------------------------------------------------------
RPL.Store = {}
local Store = RPL.Store

local SECTION = "RaidPartyLeader"
local data = nil

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
	if data.autoRetry == nil then data.autoRetry = true end
	data.classes = data.classes or {}
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

-- Сохранённое формирование с тем же типом и тем же составом (по никам), новые — первыми
function Store.FindMatch( kind, names )
	local want = {}
	local n = 0
	for _, name in ipairs( names ) do want[ name ] = true n = n + 1 end
	for i = #data.list, 1, -1 do
		local f = data.list[ i ]
		if f.kind == kind and #( f.members or {} ) == n then
			local same = true
			for _, m in ipairs( f.members ) do
				if not want[ m.n ] then same = false break end
			end
			if same then return f.id end
		end
	end
end

-- Похожее сохранённое, когда точного совпадения нет: например, вышел из отряда и
-- вернулся, а там уже кого-то не хватает или есть новенький.
-- Считаем только других игроков (не себя). Подходит формирование того же рода
-- (группа / отряд), где сейчас есть хотя бы 2 его участника, и это не меньше
-- половины его участников и не меньше половины текущего состава.
-- Лучшее — где совпадает больше игроков; при равенстве — тот же тип, затем новее.
function Store.FindBest( kind, names, me )
	local here = {}
	local nowOthers = 0
	for _, name in ipairs( names ) do
		if name ~= me then here[ name ] = true nowOthers = nowOthers + 1 end
	end
	local best, bestScore = nil, nil
	for i = #data.list, 1, -1 do
		local f = data.list[ i ]
		if RPL.IsRaidKind( f.kind ) == RPL.IsRaidKind( kind ) then
			local present, others = 0, 0
			for _, m in ipairs( f.members or {} ) do
				if m.n ~= me then
					others = others + 1
					if here[ m.n ] then present = present + 1 end
				end
			end
			if present >= 2 and present * 2 >= others and present * 2 >= nowOthers then
				local score = present * 2 + ( f.kind == kind and 1 or 0 )
				if not bestScore or score > bestScore then best, bestScore = f.id, score end
			end
		end
	end
	return best
end

function Store.NextId()
	return data and data.nextId or 1
end

function Store.GetAutoRetry()
	return data and data.autoRetry and true or false
end

function Store.SetAutoRetry( v )
	data.autoRetry = v and true or false
	Save()
end
