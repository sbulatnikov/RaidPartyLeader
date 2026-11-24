-- Заглушки игрового API для прогона скриптов RaidPartyLeader в texlua (Lua 5.3).
-- Мир — STATE: состав группы/отряда, лидер, права, дележ. Приглашения пишутся в INVITES,
-- «игроки» принимают их функцией ACCEPT( ник [, группа] ).
function Global( n, v ) _G[ n ] = v end
unpack = unpack or table.unpack

local WSmt = { __eq = function( a, b ) return a.s == b.s end }
local function WSt( s ) return setmetatable( { s = s }, WSmt ) end
local rawtype = type
local UIDS = {}
function UID( n )
	local u = UIDS[ n ]
	if not u then u = { __uid = n } UIDS[ n ] = u end
	return u
end
function type( v ) if rawtype( v ) == "table" and ( getmetatable( v ) == WSmt or v.__uid ) then return "userdata" end return rawtype( v ) end
function apitype( v )
	if rawtype( v ) == "table" and getmetatable( v ) == WSmt then return "WString" end
	if rawtype( v ) == "table" and v.__uid then return "UniqueId" end
	return rawtype( v )
end
local function S( w ) return rawtype( w ) == "table" and w.s or w end

function deep( t ) if rawtype( t ) ~= "table" or getmetatable( t ) or t.__uid then return t end local r = {} for k, v in pairs( t ) do r[ k ] = deep( v ) end return r end
CHAT, CONFIG, GCONFIG = {}, {}, {}
userMods = {
	ToWString = function( s ) return WSt( s ) end,
	FromWString = function( w ) if rawtype( w ) == "table" and getmetatable( w ) == WSmt then return w.s end error( "not WString" ) end,
	GetAvatarConfigSection = function( n ) return CONFIG[ n ] and deep( CONFIG[ n ] ) end,
	SetAvatarConfigSection = function( n, t ) CONFIG[ n ] = deep( t ) end,
	GetGlobalConfigSection = function( n ) return GCONFIG[ n ] and deep( GCONFIG[ n ] ) end,
	SetGlobalConfigSection = function( n, t ) GCONFIG[ n ] = deep( t ) end,
	SendSelfChatMessage = function( w, lvl ) CHAT[ #CHAT + 1 ] = "[" .. tostring( lvl ) .. "] " .. w.s end,
}
EVENTS, REACTIONS = {}, {}
NOW = 100000
DATE = { y = 2026, m = 11, d = 15, h = 21, min = 40, s = 0 }
common = {
	GetAddonName = function() return "RaidPartyLeader" end,
	RegisterEventHandler = function( f, ev ) local prev = EVENTS[ ev ] EVENTS[ ev ] = prev and function( p ) prev( p ) f( p ) end or f end,
	UnRegisterEventHandler = function() end,
	RegisterReactionHandler = function( f, r ) REACTIONS[ r ] = f end,
	GetAbsTimeMs = function() return NOW end,
	GetLocalDateTime = function() return deep( DATE ) end,
	GetAddonRelatedTextureGroup = function() return { HasTexture = function() return true end, GetTexture = function( _, k ) return "tex:" .. k end } end,
	GetPosConverterParams = function() return { realSizeX = 1920, realSizeY = 1080, fullVirtualSizeX = 1920, fullVirtualSizeY = 1080 } end,
	SetCursor = function() end,
}

-- Виджеты: любой ребёнок создаётся по запросу, неизвестные методы — пустые
local Widget = {}
Widget.__index = function( w, k ) if Widget[ k ] then return Widget[ k ] end if string.match( k, "^%u" ) then return function() end end return nil end
local all = {}
local function NewW( name, parent )
	local w = setmetatable( { name = name, parent = parent, kids = {}, visible = true, text = "", enabled = true,
		pl = { posX = 0, posY = 0, sizeX = 10, sizeY = 10, highPosX = 0 } }, Widget )
	all[ #all + 1 ] = w
	return w
end
function Widget.GetName( w ) return w.name end
function Widget.SetName( w, n ) w.name = n end
function Widget.GetParent( w ) return w.parent end
function Widget.GetChildChecked( w, n, rec )
	if not w.kids[ n ] then w.kids[ n ] = NewW( n, w ) end
	return w.kids[ n ]
end
function Widget.Show( w, on ) w.visible = on end
function Widget.IsVisible( w ) return w.visible end
function Widget.SetVal( w, tag, v ) w.val = w.val or {} w.val[ tag ] = v.s end
function Widget.SetVariant( w, v ) w.variant = v end
function Widget.SetBackgroundTexture( w, t ) w.tex = t end
function Widget.GetPlacementPlain( w ) return deep( w.pl ) end
function Widget.SetPlacementPlain( w, p ) w.pl = deep( p ) end
function Widget.GetRealRect( w ) return { x1 = 10, y1 = 10, x2 = 50, y2 = 30 } end
function Widget.GetText( w ) return WSt( w.text ) end
function Widget.SetText( w, t ) w.text = t.s end
function Widget.Enable( w, on ) w.enabled = on end
function Widget.SetFade( w, a ) w.fade = a end
function Widget.GetInstanceId( w ) return tostring( w ) end
function Widget.DNDRegisterGeneric() return #all end
function Widget.GetWidgetDesc( w ) return { from = w.name } end
function Widget.CreateChildByDesc( w, d ) return NewW( d.from, w ) end
mainForm = NewW( "RaidPartyLeader" )
function FIND( name ) return mainForm:GetChildChecked( name, true ) end
function TEXT( name ) local w = FIND( name ) return w.val and ( w.val.value or w.val.button_label ) or "" end

--------------------------------------------------------------------------------
-- Мир
--------------------------------------------------------------------------------
KBF_NONE, KBF_SHIFT, KBF_ALT, KBF_CTRL = 0, 2, 4, 8
LOOT_SCHEME_TYPE_FREE_FOR_ALL, LOOT_SCHEME_TYPE_GROUP, LOOT_SCHEME_TYPE_MASTER = 1, 2, 3
ITEM_QUALITY_JUNK, ITEM_QUALITY_GOODS, ITEM_QUALITY_COMMON, ITEM_QUALITY_UNCOMMON = 0, 1, 2, 3
ITEM_QUALITY_RARE, ITEM_QUALITY_EPIC, ITEM_QUALITY_LEGENDARY, ITEM_QUALITY_RELIC = 4, 5, 6, 7
RAID_MEMBER_STATE_OFFLINE, GROUP_MEMBER_STATE_OFFLINE, GROUP_MEMBER_STATE_MERC = 9, 9, 8
RAID_MEMBER_RIGHT_LEADER_HELPER, RAID_MEMBER_RIGHT_LOOT_MASTER = 1, 2
READY_CHECK_READY_STATE_READY, READY_CHECK_READY_STATE_NOT_READY = 1, 2

ME = "Аргенар"
MY_ID = 1
CLS = {}           -- [ник] = класс
-- kind: none | party | small | raid; groups: { { ник, ... }, ... }
STATE = { kind = "none", groups = {}, leader = ME, helpers = {}, loot = nil, scheme = 1, quality = 2 }
INVITES = {}       -- { { to = ник, into = "group" | "raid" } }
LOG = {}           -- что аддон сделал с отрядом

function NAMES()
	local t = {}
	for _, g in ipairs( STATE.groups ) do for _, n in ipairs( g ) do t[ #t + 1 ] = n end end
	return t
end
local function where( n )
	for g, grp in ipairs( STATE.groups ) do for s, x in ipairs( grp ) do if x == n then return g, s end end end
end
local function compact() -- группы идут без пропусков
	local out = {}
	for _, g in ipairs( STATE.groups ) do if #g > 0 then out[ #out + 1 ] = g end end
	STATE.groups = out
end
function SET( kind, groups, leader )
	STATE.kind, STATE.groups, STATE.leader = kind, deep( groups ), leader or ME
	STATE.helpers, STATE.loot = {}, nil
end
function LEAVE() SET( "none", {} ) end
local CAP = { party = 1, small = 2, raid = 4 }
-- игрок принял приглашение: g — в какую группу встанет (иначе в первую со свободным местом)
function ACCEPT( n, g )
	if STATE.kind == "none" then
		SET( "party", { { ME, n } } )
		return true
	end
	if g and STATE.groups[ g ] and #STATE.groups[ g ] < 6 then table.insert( STATE.groups[ g ], n ) return true end
	for k = 1, CAP[ STATE.kind ] do
		STATE.groups[ k ] = STATE.groups[ k ] or {}
		if #STATE.groups[ k ] < 6 then table.insert( STATE.groups[ k ], n ) return true end
	end
	return false
end
local function nameOf( u ) return rawtype( u ) == "table" and u.__uid or S( u ) end
local function member( n )
	return { name = WSt( n ), uniqueId = UID( n ), id = ( n == ME ) and MY_ID or nil, state = 0, className = CLS[ n ] or "WARRIOR" }
end

avatar = {
	IsExist = function() return true end,
	GetId = function() return MY_ID end,
	GetUniqueId = function() return UID( ME ) end,
	GetFactionInfo = function() return { isSame = true } end,
}
object = {
	IsExist = function( id ) return id == MY_ID end,
	GetName = function( id ) return WSt( ME ) end,
	GetBuffsInfo = function() return {} end,
}
unit = {
	GetPlayerShardName = function() return WSt( "Нить судьбы" ) end,
	GetFactionId = function() return { GetInfo = function() return { sysName = "League" } end } end,
	GetClass = function() return { className = "WARRIOR" } end,
}
mission = { GetShardName = function() return WSt( "Нить судьбы" ) end }
cartographer = { IsOnCommon = function() return false end }
matchMaking = { GetEventProgressInfo = function() return nil end, IsAvatarInMatchMakingEvent = function() return false end }
loot = {
	GetLootScheme = function() return STATE.scheme end,
	GetMinItemQualityForLootScheme = function() return STATE.quality end,
	CanSetLootScheme = function() return STATE.leader == ME end,
	SetLootScheme = function( v ) STATE.scheme = v LOG[ #LOG + 1 ] = "scheme" end,
	SetMinItemQualityForLootScheme = function( v ) STATE.quality = v LOG[ #LOG + 1 ] = "quality" end,
}
group = {
	IsExist = function() return STATE.kind == "party" end,
	GetMembers = function() local t = {} for _, n in ipairs( STATE.groups[ 1 ] or {} ) do t[ #t + 1 ] = member( n ) end return t end,
	IsLeader = function( x ) if x == nil then return STATE.leader == ME end return nameOf( x ) == STATE.leader end,
	CanInvite = function() return STATE.leader == ME end,
	InviteByName = function( w ) INVITES[ #INVITES + 1 ] = { to = S( w ), into = "group" } end,
	KickMember = function( w ) local g, s = where( S( w ) ) if g then table.remove( STATE.groups[ g ], s ) end end,
	SetLeader = function( u ) STATE.leader = nameOf( u ) end,
	GetReadyCheckInfo = function() return nil end,
	StartReadyCheck = function() end,
}
raid = {
	IsExist = function() return STATE.kind == "raid" or STATE.kind == "small" end,
	GetMaxGroupCount = function() return CAP[ STATE.kind ] or 4 end,
	GetMembers = function()
		local t = {}
		for g, grp in ipairs( STATE.groups ) do t[ g ] = {} for _, n in ipairs( grp ) do t[ g ][ #t[ g ] + 1 ] = member( n ) end end
		return t
	end,
	IsLeader = function( u ) if u == nil then return STATE.leader == ME end return nameOf( u ) == STATE.leader end,
	GetMemberRights = function( u ) local n = nameOf( u ) local r = {} if STATE.helpers[ n ] then r[ RAID_MEMBER_RIGHT_LEADER_HELPER ] = true end if STATE.loot == n then r[ RAID_MEMBER_RIGHT_LOOT_MASTER ] = true end return r end,
	GetLeaderHelpers = function() local t = {} for n in pairs( STATE.helpers ) do t[ #t + 1 ] = UID( n ) end return t end,
	GetLootMaster = function() return STATE.loot and UID( STATE.loot ) or nil end,
	InviteByName = function( w ) INVITES[ #INVITES + 1 ] = { to = S( w ), into = "raid" } end,
	Create = function() STATE.kind = "raid" LOG[ #LOG + 1 ] = "create" end,
	CreateSmall = function() STATE.kind = "small" LOG[ #LOG + 1 ] = "createSmall" end,
	MoveMemberToGroup = function( u, g0 )
		local n = nameOf( u ) local g, s = where( n )
		table.remove( STATE.groups[ g ], s )
		STATE.groups[ g0 + 1 ] = STATE.groups[ g0 + 1 ] or {}
		table.insert( STATE.groups[ g0 + 1 ], n )
		compact() LOG[ #LOG + 1 ] = "move"
	end,
	IsolateMember = function( u )
		local n = nameOf( u ) local g, s = where( n )
		table.remove( STATE.groups[ g ], s )
		STATE.groups[ #STATE.groups + 1 ] = { n }
		compact() LOG[ #LOG + 1 ] = "isolate"
	end,
	SwapMembers = function( a, b )
		local na, nb = nameOf( a ), nameOf( b )
		local ga, sa = where( na ) local gb, sb = where( nb )
		STATE.groups[ ga ][ sa ], STATE.groups[ gb ][ sb ] = nb, na
		LOG[ #LOG + 1 ] = "swap"
	end,
	AddRight = function( u, r ) local n = nameOf( u ) if r == RAID_MEMBER_RIGHT_LEADER_HELPER then STATE.helpers[ n ] = true else STATE.loot = n end LOG[ #LOG + 1 ] = "right" end,
	RemoveRight = function( u, r ) local n = nameOf( u ) if r == RAID_MEMBER_RIGHT_LEADER_HELPER then STATE.helpers[ n ] = nil elseif STATE.loot == n then STATE.loot = nil end end,
	Kick = function( u ) local g, s = where( nameOf( u ) ) if g then table.remove( STATE.groups[ g ], s ) compact() end end,
	ChangeLeader = function( u ) STATE.leader = nameOf( u ) end,
	GetReadyCheckInfo = function() return nil end,
	StartReadyCheck = function() end,
}
