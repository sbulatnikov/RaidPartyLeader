--------------------------------------------------------------------------------
-- RaidPartyLeader / Game.lua
-- Чтение текущей группы/отряда и действия над ними через Lua API игры.
--------------------------------------------------------------------------------
RPL.Game = {}
local G = RPL.Game

--------------------------------------------------------------------------------
-- Класс и аспект — всегда вычисляются в моменте
--------------------------------------------------------------------------------
local ASPECT_BY_SYS = {
	aspect_heal = "HEAL",
	aspect_support = "SUPPORT",
}
local aspectCache = {}       -- [objectId] = { k = "HEAL", t = tick }
local unknownAspects = {}    -- sysName -> true (уже записан в лог)

local function has( s, sub )
	return string.find( s, sub, 1, true ) ~= nil
end

local function AspectFromSysName( sys )
	local k = ASPECT_BY_SYS[ sys ]
	if k or not has( sys, "aspect" ) then return k end
	if has( sys, "tank" ) or has( sys, "def" ) or has( sys, "protect" ) or has( sys, "guard" ) then return "TANK" end
	if has( sys, "heal" ) then return "HEAL" end
	if has( sys, "support" ) or has( sys, "buff" ) then return "SUPPORT" end
	if has( sys, "damage" ) or has( sys, "attack" ) or has( sys, "offen" ) or has( sys, "dps" ) or has( sys, "_dd" ) or has( sys, "assault" ) then return "DAMAGE" end
	--@debug
	if not unknownAspects[ sys ] then
		unknownAspects[ sys ] = true
		RPL.Log( "unknown aspect sysName:", sys )
	end
	--@end
end

local function AspectFromName( name )
	if not has( name, RPL.L.aspectWord ) then return nil end
	for k, part in pairs( RPL.L.aspectNames ) do
		if has( name, part ) then return k end
	end
end

-- Ожидаем: участник далеко или вне сети — объекта нет, данные юнита (класс, аспект, сервер) не читаем
local function Exists( objectId )
	return objectId ~= nil and object.IsExist( objectId ) and true or false
end

function G.Aspect( objectId )
	if not Exists( objectId ) then return nil end
	local c = aspectCache[ objectId ]
	if c and RPL.tick - c.t < 3 then return c.k end
	local k = nil
	local infos = object.GetBuffsInfo( objectId, true, false )
	if type( infos ) == "table" then
		for _, info in pairs( infos ) do
			local sys = type( info.sysName ) == "string" and string.lower( info.sysName ) or ""
			k = AspectFromSysName( sys ) or AspectFromName( RPL.S( info.name ) )
			if k then break end
		end
	end
	aspectCache[ objectId ] = { k = k, t = RPL.tick }
	return k
end

local function ClassKey( m )
	local c = m.className
	if ( type( c ) ~= "string" or c == "" ) and Exists( m.id ) then
		local info = unit.GetClass( m.id )
		-- Ожидаем: GetClass возвращает nil, если данные недоступны
		if type( info ) == "table" then c = info.className end
	end
	c = type( c ) == "string" and string.upper( c ) or ""
	if c ~= "" and RPL.Tex( "Classes", c ) then return c end
	return "UNKNOWN"
end

--------------------------------------------------------------------------------
-- Чтение состояния
-- st = {
--   kind = "none" | "party" | "raid" | "small", me = "Ник",
--   groups = { [g] = { e, ... } }, groupCount = n, list = { e, ... }, byName = { [ник] = e },
--   leader = "Ник", isLeader, canManage, canInvite,
-- }
-- e = { name, uid, id, g, s, cls, asp, offline, leader, assist, loot }
--------------------------------------------------------------------------------
function G.AvatarName()
	if avatar.IsExist() then return RPL.S( object.GetName( avatar.GetId() ) ) end
	return ""
end

-- [memberUniqueId] = classKey. UniqueId — индексируемая userdata: ключ по значению (проверено в игре)
local classByMember = {}

--------------------------------------------------------------------------------
-- Межсерверные и межфракционные формирования (проверено в «Битве за Каргаллас»):
--   unit.GetPlayerShardName( id ) -> WString «Нить судьбы» / «Звезда Удачи»;
--   unit.GetFactionId( id ) -> FactionId, :GetInfo().sysName = "League" / "Empire",
--   avatar.GetFactionInfo( f ).isSame — фракция аватара.
-- Обе функции требуют id (игрок рядом). Иначе — matchMaking.GetEventProgressInfo().members
-- (там есть name, shardName, factionId). Сервер и фракция не меняются: кэш по uniqueId.
--------------------------------------------------------------------------------
local crossByUid = {}
local myShard = nil

local function FactionOf( fid )
	if not fid then return nil, nil end
	local sys = nil
	local info = fid:GetInfo()
	if type( info ) == "table" and type( info.sysName ) == "string" then sys = string.lower( info.sysName ) end
	local same = nil
	local fi = avatar.GetFactionInfo( fid )
	if type( fi ) == "table" then same = fi.isSame and true or false end
	return sys, same
end

-- Ожидаем: сведений об инстанс-ивенте может не быть. matchMaking.GetEventProgressInfo без них падает
-- с ошибкой «can't get Replica::EventProgress object» (так было у 0.9.5 в mods.txt), и движок пишет её
-- в журнал даже под перехватом. Поэтому зовём её только по событию EVENT_MATCH_MAKING_EVENT_PROGRESS_ADDED —
-- им игра сообщает, что сведения появились, — и держим участников до следующего такого события.
local eventMembers = {}   -- [ник] = участник из matchMaking.GetEventProgressInfo().members

function G.OnEventProgress()
	eventMembers = {}
	local pi = matchMaking.GetEventProgressInfo()
	if type( pi ) == "table" and type( pi.members ) == "table" then
		for _, m in pairs( pi.members ) do
			local n = RPL.S( m.name )
			if n ~= "" then eventMembers[ n ] = m end
		end
	end
end

local function ProgressByName()
	return eventMembers
end

local function CrossInfo( m, name )
	local c = m.uniqueId and crossByUid[ m.uniqueId ]
	if c then return c end
	c = nil
	if Exists( m.id ) then
		local sh = unit.GetPlayerShardName( m.id )
		local fac, same = FactionOf( unit.GetFactionId( m.id ) )
		c = { shard = sh and RPL.S( sh ) or nil, fac = fac, same = same }
	else
		local p = ProgressByName()[ name ]
		if p then
			local fac, same = FactionOf( p.factionId )
			c = { shard = p.shardName and RPL.S( p.shardName ) or nil, fac = fac, same = same }
		end
	end
	if c and m.uniqueId and c.shard and c.same ~= nil then crossByUid[ m.uniqueId ] = c end
	return c
end

-- Короткая метка сервера: первые буквы слов («Звезда Удачи» -> «ЗУ»)
function G.ShardTag( shard )
	if not shard or shard == "" then return "" end
	local tag = ""
	for w in string.gmatch( shard, "[^%s%-]+" ) do tag = tag .. string.sub( w, 1, 1 ) end
	return tag
end

local light = false -- G.Read( true ): без аспектов (окно закрыто)

local function AddMember( st, g, s, m, isRaid, solo )
	local name = RPL.S( m.name )
	if name == "" then return end
	local e = { name = name, uid = m.uniqueId, id = m.id, g = g, s = s, live = true }
	if isRaid then
		e.offline = ( m.state == RAID_MEMBER_STATE_OFFLINE )
	else
		e.offline = ( m.state == GROUP_MEMBER_STATE_OFFLINE )
	end
	-- класс персонажа не меняется: запоминаем один раз (по ID в сессии, по нику в конфиге),
	-- потому что у участника вне игры className не приходит
	local cls = ( m.uniqueId and classByMember[ m.uniqueId ] ) or RPL.Store.GetClass( name )
	if not cls then
		local k = ClassKey( m )
		if k ~= "UNKNOWN" then
			cls = k
			if m.uniqueId then classByMember[ m.uniqueId ] = k end
			RPL.Store.SetClass( name, k )
		end
	elseif m.uniqueId and not classByMember[ m.uniqueId ] then
		classByMember[ m.uniqueId ] = cls
	end
	e.cls = cls or "UNKNOWN"
	-- сервер и фракция: чужие не сохраняются и в сравнении с сохранённым не участвуют
	local c = CrossInfo( m, name )
	if c then
		e.shard, e.fac, e.sameFac = c.shard, c.fac, c.same
		e.foreign = ( c.shard and myShard and c.shard ~= myShard ) or ( c.same == false ) or false
		if c.shard and myShard and c.shard ~= myShard then st.crossShard = true end
		if c.same == false then st.crossFaction = true end
	end
	e.asp = ( not e.offline and not light ) and G.Aspect( m.id ) or nil
	if isRaid then
		if e.uid then
			e.leader = raid.IsLeader( e.uid ) and true or false
			local rights = raid.GetMemberRights( e.uid )
			if type( rights ) == "table" then
				-- по документации { [право] = true }, но принимаем и список { право, ... }
				for k, v in pairs( rights ) do
					if k == RAID_MEMBER_RIGHT_LEADER_HELPER or v == RAID_MEMBER_RIGHT_LEADER_HELPER then e.assist = true end
					if k == RAID_MEMBER_RIGHT_LOOT_MASTER or v == RAID_MEMBER_RIGHT_LOOT_MASTER then e.loot = true end
				end
			end
		end
	elseif not solo then
		e.leader = group.IsLeader( e.uid or m.name ) and true or false
	end
	st.groups[ g ] = st.groups[ g ] or {}
	table.insert( st.groups[ g ], e )
	table.insert( st.list, e )
	-- одинаковые ники на разных серверах: свой игрок важнее, чужой — под «ник@сервер»
	local prev = st.byName[ name ]
	if prev and e.foreign and not prev.foreign then
		st.byName[ name .. "@" .. tostring( e.shard ) ] = e
	else
		st.byName[ name ] = e
	end
	if not e.foreign then st.ownCount = ( st.ownCount or 0 ) + 1 end
	if e.leader then st.leader = name end
	if name == st.me then st.meEntry = e end
end

function G.Read( lightRead )
	light = lightRead and true or false
	local st = { kind = "none", me = G.AvatarName(), groups = {}, groupCount = 0, list = {}, byName = {}, ownCount = 0 }
	if not myShard and avatar.IsExist() then
		local sh = unit.GetPlayerShardName( avatar.GetId() )
		if sh then myShard = RPL.S( sh ) end
	end
	st.myShard = myShard
	if raid.IsExist() then
		local max = raid.GetMaxGroupCount() or 4
		st.kind = ( max <= 2 ) and "small" or "raid"
		local groups = raid.GetMembers()
		if type( groups ) == "table" then
			-- ВНИМАНИЕ: считаем, что индекс в списке = номер группы (проверить в игре)
			for g, grp in ipairs( groups ) do
				st.groups[ g ] = st.groups[ g ] or {}
				for s, m in ipairs( grp ) do AddMember( st, g, s, m, true ) end
				-- группы идут без пропусков: считаем по последней непустой
				if #st.groups[ g ] > 0 then st.groupCount = g end
			end
		end
		-- второй источник ролей: списки помощников и ответственного за добычу.
		-- UniqueId индексируемый, поэтому подходит как ключ таблицы.
		local helperSet = {}
		local helpers = raid.GetLeaderHelpers()
		-- Ожидаем: GetLeaderHelpers может вернуть nil — помощников нет
		if type( helpers ) == "table" then
			for _, uid in pairs( helpers ) do helperSet[ uid ] = true end
		end
		-- Ожидаем: ответственного за добычу может не быть — GetLootMaster возвращает nil
		local lootMaster = raid.GetLootMaster()
		for _, e in ipairs( st.list ) do
			if e.uid then
				if helperSet[ e.uid ] then e.assist = true end
				if lootMaster and lootMaster == e.uid then e.loot = true end
			end
		end
		st.isLeader = raid.IsLeader() and true or false
		st.canManage = st.isLeader or ( st.meEntry and st.meEntry.assist ) or false
		-- raid.CanInvite не вызываем: без аргумента движок пишет ошибку
		-- «wrong params count (0, should be 1)» на каждый вызов. Приглашать в отряд
		-- могут лидер и помощники — это и есть canManage.
		st.canInvite = st.canManage and true or false
	elseif group.IsExist() then
		st.kind = "party"
		st.groupCount = 1
		st.groups[ 1 ] = {}
		local members = group.GetMembers() or {}
		local s = 0
		for _, m in ipairs( members ) do
			if m.state ~= GROUP_MEMBER_STATE_MERC then
				s = s + 1
				AddMember( st, 1, s, m, false )
			end
		end
		st.isLeader = group.IsLeader() and true or false
		st.canManage = st.isLeader
		st.canInvite = group.CanInvite() and true or false
	else
		st.canInvite = true
		-- Вне группы список участников пуст, а себя мы не приглашаем — и при сборе аватара
		-- не было видно. Показываем себя первым в первой группе: там и окажешься, когда
		-- кто-нибудь примет приглашение.
		if avatar.IsExist() then
			local myId = avatar.GetId()
			AddMember( st, 1, 1, { name = object.GetName( myId ), uniqueId = avatar.GetUniqueId(), id = myId }, false, true )
		end
	end
	-- проверку запускают лидер и помощники отряда; в группе — лидер
	st.canReady = ( RPL.IsRaidKind( st.kind ) and st.canManage or st.kind == "party" and st.isLeader ) and true or false
	-- состояние проверки готовности: пока идёт и ещё немного после окончания
	if RPL.readyShow and st.kind ~= "none" then
		local r = G.ReadyInfo( st.kind )
		if r then
			st.readyActive = r.active
			for _, e in ipairs( st.list ) do
				if e.uid then e.ready = r.byUid[ e.uid ] end
			end
		end
	end
	-- дележ добычи и минимальная ценность
	if st.kind ~= "none" then
		local s = RPL.SchemeByEnum( loot.GetLootScheme() )
		local q = RPL.QualityByEnum( loot.GetMinItemQualityForLootScheme() )
		st.lootScheme = s and s.key or nil
		st.lootQuality = q and q.key or nil
		st.canLoot = ( st.isLeader and loot.CanSetLootScheme() ) and true or false
	end
	return st
end

--------------------------------------------------------------------------------
-- Проверка готовности (raid/group.GetReadyCheckInfo: members [0..] = { uniqueId, state })
--------------------------------------------------------------------------------
local function ReadyKey( state )
	if state == READY_CHECK_READY_STATE_READY then return "ready" end
	if state == READY_CHECK_READY_STATE_NOT_READY then return "notready" end
	return "wait"
end

-- nil, если проверки не было; иначе { active, byUid = { [uniqueId] = "ready"|"notready"|"wait" } }
function G.ReadyInfo( kind )
	local lib = RPL.IsRaidKind( kind ) and raid or ( kind == "party" and group ) or nil
	if not lib then return nil end
	local info = lib.GetReadyCheckInfo()
	-- Ожидаем: если проверки готовности ещё не было, GetReadyCheckInfo возвращает nil
	if type( info ) ~= "table" then return nil end
	local r = { active = info.isInProgress and true or false, byUid = {} }
	for _, m in pairs( info.members or {} ) do
		if m.uniqueId then r.byUid[ m.uniqueId ] = ReadyKey( m.state ) end
	end
	return r
end

function G.StartReadyCheck( kind )
	if RPL.IsRaidKind( kind ) then raid.StartReadyCheck()
	elseif kind == "party" then group.StartReadyCheck() end
end

function G.SetLootScheme( key )
	local s = RPL.Scheme( key )
	if s then loot.SetLootScheme( s.enum ) end
end

-- Порог действует для текущей схемы, поэтому схему всегда выставляем первой
function G.SetLootQuality( key )
	local q = RPL.Quality( key )
	if q then loot.SetMinItemQualityForLootScheme( q.enum ) end
end

--------------------------------------------------------------------------------
-- Действия
--------------------------------------------------------------------------------
function G.Invite( name )
	local w = RPL.WS( name )
	if raid.IsExist() then
		raid.InviteByName( w )
	else
		group.InviteByName( w )
	end
end

function G.Convert( kind )
	if kind == "small" then raid.CreateSmall() else raid.Create() end
end

-- Можно ли перенести участника e в группу g (с единицы).
-- Группы заполняются по порядку: новая — только следующая за последней занятой,
-- и только если игрок не единственный в последней группе (иначе она просто исчезнет).
-- Возвращает true или false и текст причины.
function G.CanMoveTo( st, e, g )
	if not e or not e.uid or not RPL.IsRaidKind( st.kind ) or e.g == g then return false end
	if g > RPL.KindGroups( st.kind ) then return false end
	-- последний игрок группы не может уйти в группу с бОльшим номером: его группа
	-- исчезнет, следующие сдвинутся, и он окажется там же (отряд сжимает группы)
	if g > e.g and #( st.groups[ e.g ] or {} ) <= 1 then
		return false, RPL.F( RPL.L.toastAlone, e.name, e.g )
	end
	if g <= st.groupCount then
		if #( st.groups[ g ] or {} ) >= RPL.GROUP_SIZE then return false, RPL.F( RPL.L.toastFull, g ) end
		return true
	end
	if g > st.groupCount + 1 then return false, RPL.F( RPL.L.toastSkip, st.groupCount + 1 ) end
	return true
end

-- g — номер группы с единицы. Следующая новая группа создаётся через IsolateMember.
function G.Move( st, e, g )
	if not G.CanMoveTo( st, e, g ) then return false end
	if g <= st.groupCount then
		raid.MoveMemberToGroup( e.uid, g - 1 )
	else
		raid.IsolateMember( e.uid )
	end
	return true
end

-- Обмен двух участников отряда — и между группами, и внутри одной группы.
-- Документация пишет «в разных группах», но интерфейс самого клиента
-- (Raid/ClassDragNDropPlate) меняет местами любые две карточки через SwapMembers.
function G.Swap( st, a, b )
	if RPL.IsRaidKind( st.kind ) and a.uid and b.uid and a.name ~= b.name then
		raid.SwapMembers( a.uid, b.uid )
		return true
	end
	return false
end

function G.SetLeader( st, e )
	if not e.uid then return end
	if RPL.IsRaidKind( st.kind ) then raid.ChangeLeader( e.uid )
	elseif st.kind == "party" then group.SetLeader( e.uid ) end
end

function G.Kick( st, e )
	if RPL.IsRaidKind( st.kind ) then
		if e.uid then raid.Kick( e.uid ) end
	elseif st.kind == "party" then
		group.KickMember( RPL.WS( e.name ) )
	end
end

local function ToggleRight( e, right, has )
	if not e.uid then return end
	if has then raid.RemoveRight( e.uid, right ) else raid.AddRight( e.uid, right ) end
end

function G.ToggleAssist( e )
	ToggleRight( e, RAID_MEMBER_RIGHT_LEADER_HELPER, e.assist )
end

function G.ToggleLoot( e )
	ToggleRight( e, RAID_MEMBER_RIGHT_LOOT_MASTER, e.loot )
end

function G.GiveAssist( e )
	if e.uid and not e.assist then raid.AddRight( e.uid, RAID_MEMBER_RIGHT_LEADER_HELPER ) end
end

function G.GiveLoot( e )
	if e.uid and not e.loot then raid.AddRight( e.uid, RAID_MEMBER_RIGHT_LOOT_MASTER ) end
end
