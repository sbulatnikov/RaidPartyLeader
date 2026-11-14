--------------------------------------------------------------------------------
-- RaidPartyLeader / Probe.lua  (temporary diagnostics, remove after testing)
-- Chat command: /rplprobe   ->  results go to Personal\Logs\mods.txt
-- Checks how UniqueId behaves: indexable userdata?, == by value?, works as a
-- table key?, stable tostring?, same value from different API sources?,
-- survives saving to the avatar config and relog?
-- ASCII only on purpose: no encoding questions for this file.
--------------------------------------------------------------------------------
local SECTION = "RaidPartyLeaderProbe"
local run = 0
local eventsLogged = 0
local EVENTS_LIMIT = 60
local lastSeen = {}   -- [name] = uniqueId from the last probe

local function S( v )
	if v == nil then return "nil" end
	if type( v ) == "string" then return v end
	if type( v ) == "boolean" or type( v ) == "number" then return tostring( v ) end
	local ok, r = pcall( userMods.FromWString, v )
	if ok and type( r ) == "string" then return r end
	return tostring( v )
end

local function L( ... )
	local parts = {}
	for i = 1, select( "#", ... ) do parts[ #parts + 1 ] = S( ( select( i, ... ) ) ) end
	local text = "[RPL probe] " .. table.concat( parts, "" )
	-- chat: System -> Addons (the client log file is often switched off)
	local ok = pcall( userMods.SendSelfChatMessage, userMods.ToWString( text ), "notice" )
	if not ok then pcall( common.LogInfo, "common", text ) end
end

local function Safe( f, ... )
	local ok, r = pcall( f, ... )
	if ok then return r end
	return "ERR(" .. tostring( r ) .. ")"
end

local function Eq( a, b )
	if a == nil or b == nil then return "n/a" end
	return tostring( Safe( function() return a == b end ) )
end

local function AsKey( a, b )
	if a == nil or b == nil then return "n/a" end
	return tostring( Safe( function()
		local t = {}
		t[ a ] = true
		return t[ b ] == true
	end ) )
end

-- { [1] = { member, ... }, ... } for both raid and party
local function ReadGroups()
	if raid.IsExist() then
		return Safe( raid.GetMembers ), "raid"
	elseif group.IsExist() then
		return { group.GetMembers() or {} }, "party"
	end
	return {}, "none"
end

local function MemberInfo( kind, id )
	if kind == "raid" then return Safe( raid.GetMemberInfo, id ) end
	if kind == "party" then return Safe( group.GetMemberInfo, id ) end
end

local function ProbeSelf()
	local me1, me2 = avatar.GetUniqueId(), avatar.GetUniqueId()
	L( "self: apitype=", Safe( apitype, me1 ), " indexable=", Safe( isindexableudata, me1 ),
		" tostring=", tostring( me1 ), " / ", tostring( me2 ),
		" rawequal=", rawequal( me1, me2 ), " ==", Eq( me1, me2 ), " key=", AsKey( me1, me2 ) )
	return me1
end

local function ProbeConfig( me, groups )
	-- what was saved by the previous probe (possibly before a relog)
	local prev = Safe( userMods.GetAvatarConfigSection, SECTION )
	if type( prev ) == "table" then
		L( "config prev: run=", prev.run, " meStr=", prev.meStr, " nowStr=", tostring( me ),
			" strSame=", prev.meStr == tostring( me ),
			" storedType=", Safe( apitype, prev.me ), " stored==now=", Eq( prev.me, me ) )
		if type( prev.members ) == "table" then
			for name, str in pairs( prev.members ) do
				L( "config prev member: ", name, " str=", str )
			end
		end
	else
		L( "config prev: ", prev )
	end
	local members = {}
	for _, list in ipairs( type( groups ) == "table" and groups or {} ) do
		for _, m in ipairs( list ) do
			if m.uniqueId then members[ S( m.name ) ] = tostring( m.uniqueId ) end
		end
	end
	local data = { run = run, me = me, meStr = tostring( me ), members = members }
	local ok, err = pcall( userMods.SetAvatarConfigSection, SECTION, data )
	if not ok then
		L( "config save with userdata FAILED: ", err, " -> saving strings only" )
		data.me = nil
		ok, err = pcall( userMods.SetAvatarConfigSection, SECTION, data )
	end
	L( "config save ok=", ok, ok and "" or ( " err=" .. tostring( err ) ) )
end

local function ProbeMembers( me, first, kind )
	local second = ReadGroups()
	local leader = kind == "raid" and Safe( raid.GetLeader ) or ( kind == "party" and Safe( group.GetLeader ) ) or nil
	local helpers = kind == "raid" and Safe( raid.GetLeaderHelpers ) or nil
	local count = 0
	for g, list in ipairs( type( first ) == "table" and first or {} ) do
		for i, m in ipairs( list ) do
			local name = S( m.name )
			local a = m.uniqueId
			if not a then
				L( "member ", name, " g", g, " #", i, ": uniqueId=nil state=", m.state, " (merc?)" )
			else
				count = count + 1
				local b = type( second ) == "table" and second[ g ] and second[ g ][ i ] and second[ g ][ i ].uniqueId or nil
				local bName = b and S( second[ g ][ i ].name ) or "?"
				local info = MemberInfo( kind, m.name )
				local c = type( info ) == "table" and info.uniqueId or nil
				local byUid = MemberInfo( kind, a )
				local isHelper = "n/a"
				if type( helpers ) == "table" then
					isHelper = "false"
					for _, h in pairs( helpers ) do
						if Safe( function() return h == a end ) == true then isHelper = "true" end
					end
				end
				L( "member ", name, " g", g, " #", i, " state=", m.state, " id=", m.id,
					" | str=", tostring( a ), " / ", tostring( b ), ( bName ~= name and ( " (2nd read is " .. bName .. ")" ) or "" ),
					" | rawequal=", rawequal( a, b ), " a==b=", Eq( a, b ), " key=", AsKey( a, b ),
					" | ==byName=", Eq( a, c ), " byUid.name=", type( byUid ) == "table" and byUid.name or byUid,
					" | ==leader=", Eq( a, leader ), " helper=", isHelper,
					" | ==me=", Eq( a, me ),
					" | ==lastProbe=", Eq( a, lastSeen[ name ] ), " lastStr=", lastSeen[ name ] and tostring( lastSeen[ name ] ) or "nil" )
				lastSeen[ name ] = a
			end
		end
	end
	L( "members with uniqueId: ", count )
end

local function Probe()
	run = run + 1
	local groups, kind = ReadGroups()
	L( "===== run ", run, " kind=", kind, " onCommonMap=", Safe( cartographer.IsOnCommon ),
		" shard=", Safe( mission.GetShardName ) )
	local me = ProbeSelf()
	ProbeMembers( me, groups, kind )
	ProbeConfig( me, groups )
	L( "===== end run ", run )
	-- visible confirmation in game (the client log may be switched off)
	if RPL and RPL.Toast then RPL.Toast( "RPL probe #" .. run .. " done: see chat (System - Addons)" ) end
end

-- MEMBER_CHANGED carries its own uniqueId: compare with what GetMembers returned
local function OnMemberChanged( p )
	if eventsLogged >= EVENTS_LIMIT then return end
	eventsLogged = eventsLogged + 1
	local name = S( p.name )
	local kind = raid.IsExist() and "raid" or "party"
	local info = MemberInfo( kind, p.name )
	local fromInfo = type( info ) == "table" and info.uniqueId or nil
	L( "event ", kind, " MEMBER_CHANGED ", name, " id=", p.id, " str=", tostring( p.uniqueId ),
		" | ==info=", Eq( p.uniqueId, fromInfo ), " key=", AsKey( p.uniqueId, fromInfo ),
		" | ==lastProbe=", Eq( p.uniqueId, lastSeen[ name ] ),
		" | state=", type( info ) == "table" and info.state or "?" )
end

common.RegisterEventHandler( function( p )
	local text = string.lower( S( p.text ) )
	if string.find( text, "rplprobe", 1, true ) then
		local ok, err = pcall( Probe )
		if not ok then
			L( "probe ERROR: ", err )
			if RPL and RPL.Toast then RPL.Toast( "RPL probe error: " .. tostring( err ) ) end
		end
	end
end, "EVENT_UNKNOWN_SLASH_COMMAND" )
common.RegisterEventHandler( OnMemberChanged, "EVENT_GROUP_MEMBER_CHANGED" )
common.RegisterEventHandler( OnMemberChanged, "EVENT_RAID_MEMBER_CHANGED" )
