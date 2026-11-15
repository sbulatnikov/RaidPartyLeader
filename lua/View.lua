--------------------------------------------------------------------------------
-- RaidPartyLeader / View.lua
-- Модель отображения (живые участники + ожидающие из связанного формирования)
-- и отрисовка виджетов. Сетка постоянная: 4 группы по 6 мест, лишнее скрывается
-- или выключается, размеры не меняются.
--------------------------------------------------------------------------------
RPL.View = {}
local V = RPL.View

local ui = {}
V.ui = ui

local SLOT_PARTS = { "SlotButton", "ClassIcon", "LeaderBadge", "AssistBadge", "LootBadge", "FactionBadge", "AspectIcon",
	"NameText", "StatusIcon", "SwapButton", "HomeButton", "RetryButton", "KickButton" }
local RIGHT_BUTTONS = { "SwapButton", "HomeButton", "RetryButton", "KickButton" }
-- проверка готовности: готов / не готов / ещё не ответил
local READY_ICON = { ready = "READY", notready = "DECLINED", wait = "INVITED" }
local FAC_TEX = { league = "FAC_LEAGUE", empire = "FAC_EMPIRE" }
-- участник сохранённого формирования, которого нет в составе (вышел, исключён, ещё не звали)

-- варианты SlotButton (порядок как в SlotButton.(WidgetButton).xdb)
local VAR_NORMAL, VAR_SELECTED, VAR_MISPLACED, VAR_EMPTY, VAR_TARGET = 0, 1, 2, 3, 4

function V.Init()
	ui.window = RPL.W( "RPLWindow" )
	ui.groupsPanel = RPL.W( "Groups" )
	ui.groups = {}
	for g = 1, 4 do
		local gw = RPL.Child( ui.groupsPanel, "Group" .. g )
		local header = RPL.Child( gw, "GroupHeader" )
		local grp = { w = gw, header = header, count = RPL.Child( header, "GroupCount" ), slots = {} }
		for k = 1, RPL.GROUP_SIZE do
			local sw = RPL.Child( gw, "Slot" .. k )
			local slot = { w = sw }
			for _, part in ipairs( SLOT_PARTS ) do slot[ part ] = RPL.Child( sw, part ) end
			grp.slots[ k ] = slot
		end
		ui.groups[ g ] = grp
	end
end

--------------------------------------------------------------------------------
-- Модель
--------------------------------------------------------------------------------
function V.Target( f )
	local t = {}
	if f then
		for _, m in ipairs( f.members or {} ) do t[ m.n ] = m end
	end
	return t
end

-- Порядок внутри группы — реальный, как отдаёт игра (сервер его не меняет).
-- Ожидающие из сохранённого идут после живых, в сохранённом порядке.
local function SortGroup( list, target )
	local function key( e )
		if e.live then return e.s or 0 end
		return 100 + ( e.s or 0 )
	end
	table.sort( list, function( a, b )
		local ka, kb = key( a ), key( b )
		if ka ~= kb then return ka < kb end
		return a.name < b.name
	end )
end

function V.BuildCurrent( st )
	local f = RPL.Store.Get( RPL.link )
	local target = V.Target( f )
	local ng = RPL.KindGroups( st.kind )
	if f then ng = math.max( ng, RPL.KindGroups( f.kind ) ) end
	local m = { st = st, f = f, target = target, ng = ng, groups = {}, misplaced = {}, misordered = {}, pending = {},
		invitable = 0, overflow = {}, strangers = 0, badge = false }
	for g = 1, ng do m.groups[ g ] = {} end
	for _, e in ipairs( st.list ) do
		local t = target[ e.name ]
		e.misplaced = ( t and RPL.IsRaidKind( st.kind ) and t.g ~= e.g ) and true or false
		if e.misplaced then table.insert( m.misplaced, e ) end
		-- «не из состава»: в связанном формировании его нет. Аддон таких не трогает, только помечает
		e.stranger = ( f ~= nil and st.kind ~= "none" and not t and e.name ~= st.me ) and true or false
		if e.stranger then m.strangers = m.strangers + 1 end
		if m.groups[ e.g ] then table.insert( m.groups[ e.g ], e ) end
	end
	-- Недостающих из связанного формирования показываем, пока мы в нём (или собираем его):
	-- вышел, исключили, ещё не пригласили — видно пустую роль.
	local assembling = RPL.asm and RPL.asm.active
	if f and ( assembling or st.kind ~= "none" ) then
		for _, t in ipairs( f.members or {} ) do
			if t.n ~= st.me and not st.byName[ t.n ] then
				local p = { name = t.n, pending = true, g = t.g, s = t.s, cls = RPL.Store.GetClass( t.n ) }
				table.insert( m.pending, p )
				m.badge = true
			end
		end
		table.sort( m.pending, function( a, b )
			if ( a.g or 0 ) ~= ( b.g or 0 ) then return ( a.g or 0 ) < ( b.g or 0 ) end
			return ( a.s or 0 ) < ( b.s or 0 )
		end )
		-- Мест на всех может не хватить: их занимают «не из состава». Зовём по порядку мест,
		-- последние не помещаются (m.overflow). Вне группы считаем всех: места ещё свободны.
		local free = V.FreeSlots( st, f )
		for i, p in ipairs( m.pending ) do
			if st.kind ~= "none" and i > free then
				table.insert( m.overflow, p.name )
			else
				m.invitable = m.invitable + 1
			end
		end
		for _, p in ipairs( m.pending ) do
			local g = math.min( p.g or 1, ng )
			if #m.groups[ g ] >= RPL.GROUP_SIZE then
				g = nil
				for gg = 1, ng do
					if #m.groups[ gg ] < RPL.GROUP_SIZE then g = gg break end
				end
			end
			if g then table.insert( m.groups[ g ], p ) end
		end
	end
	for g = 1, ng do SortGroup( m.groups[ g ], target ) end
	-- Порядок внутри группы: среди тех, кто уже в своей группе, сравниваем реальный
	-- порядок с сохранённым. Кто стоит не на своём месте — misordered, а orderSwap —
	-- с кем поменяться (raid.SwapMembers работает и внутри группы).
	if f and RPL.IsRaidKind( st.kind ) then
		for g = 1, ng do
			local actual = {}
			for _, e in ipairs( m.groups[ g ] ) do
				local t = e.live and target[ e.name ]
				if t and t.g == g then actual[ #actual + 1 ] = e end
			end
			local desired = {}
			for i, e in ipairs( actual ) do desired[ i ] = e end
			table.sort( desired, function( a, b ) return ( target[ a.name ].s or 0 ) < ( target[ b.name ].s or 0 ) end )
			for i, e in ipairs( actual ) do
				if desired[ i ] ~= e then
					e.misordered = true
					e.orderSwap = desired[ i ]
					table.insert( m.misordered, e )
				end
			end
		end
	end
	if #m.misplaced > 0 or #m.misordered > 0 then m.badge = true end
	return m
end

-- Сколько ещё мест в составе, если собирать в нём f: группа, которая станет отрядом,
-- считается по вместимости отряда
function V.FreeSlots( st, f )
	local kind = st.kind
	if kind == "none" or ( kind == "party" and f and RPL.IsRaidKind( f.kind ) ) then kind = f and f.kind or kind end
	return math.max( 0, RPL.KindGroups( kind ) * RPL.GROUP_SIZE - math.max( #st.list, 1 ) )
end

function V.BuildDetail( f, st )
	local ng = RPL.KindGroups( f.kind )
	local assist = RPL.Set( f.assist )
	local m = { f = f, ng = ng, groups = {}, invitable = 0, missing = 0 }
	for g = 1, ng do m.groups[ g ] = {} end
	for _, t in ipairs( f.members or {} ) do
		local g = math.max( 1, math.min( t.g or 1, ng ) )
		if #m.groups[ g ] < RPL.GROUP_SIZE then
			table.insert( m.groups[ g ], { name = t.n, s = t.s, saved = true,
				leader = ( f.leader == t.n ), assist = assist[ t.n ], loot = ( f.loot == t.n ) } )
		end
		if t.n ~= st.me and not st.byName[ t.n ] then m.missing = m.missing + 1 end
	end
	-- сколько реально позовёт «Пригласить всех» (вне группы места ещё свободны)
	m.invitable = st.kind == "none" and m.missing or math.min( m.missing, V.FreeSlots( st, f ) )
	for g = 1, ng do
		table.sort( m.groups[ g ], function( a, b ) return ( a.s or 0 ) < ( b.s or 0 ) end )
	end
	return m
end

-- Что именно отличается от сохранённого: nil, если совпадает
function V.DiffSummary( f, st )
	if not f then return nil end
	local raidKind = RPL.IsRaidKind( st.kind )
	local saved = {}
	local missing, moved = 0, 0
	for _, t in ipairs( f.members or {} ) do
		saved[ t.n ] = t
		local e = st.byName[ t.n ]
		if not e then missing = missing + 1
		elseif raidKind and e.g ~= t.g then moved = moved + 1 end
	end
	local added = 0
	for _, e in ipairs( st.list ) do
		if not saved[ e.name ] and not e.foreign then added = added + 1 end
	end
	local roles = false
	if raidKind then
		local assist = RPL.Set( f.assist )
		for _, e in ipairs( st.list ) do
			if ( e.assist and true or false ) ~= ( assist[ e.name ] and true or false )
				or ( e.loot and true or false ) ~= ( f.loot == e.name ) then
				roles = true
				break
			end
		end
	end
	local parts = {}
	if f.kind ~= st.kind and st.kind ~= "none" then parts[ #parts + 1 ] = RPL.L.diffKind end
	if missing > 0 then parts[ #parts + 1 ] = RPL.F( RPL.L.diffMissing, missing ) end
	if added > 0 then parts[ #parts + 1 ] = RPL.F( RPL.L.diffAdded, added ) end
	if roles then parts[ #parts + 1 ] = RPL.L.diffRoles end
	if st.kind ~= "none" and f.lootScheme and st.lootScheme and f.lootScheme ~= st.lootScheme then
		parts[ #parts + 1 ] = RPL.L.diffLoot
	end
	if st.kind ~= "none" and f.lootQuality and st.lootQuality and f.lootQuality ~= st.lootQuality then
		parts[ #parts + 1 ] = RPL.L.diffQuality
	end
	-- перестановки текстом не пишем: для них есть флажки и «Расставить»
	if #parts == 0 then
		if moved > 0 then return "" end -- отличается только местами
		return nil
	end
	return RPL.L.diffPrefix .. table.concat( parts, " · " )
end

-- Отличается ли текущий состав от сохранённого (состав, группы, роли, тип)
function V.Differs( f, st )
	if not f then return false end
	if f.kind ~= st.kind then return true end
	local raidKind = RPL.IsRaidKind( st.kind )
	local count = 0
	for _, t in ipairs( f.members or {} ) do
		local e = st.byName[ t.n ]
		if not e then return true end
		if raidKind and e.g ~= t.g then return true end
		count = count + 1
	end
	if count ~= ( st.ownCount or #st.list ) then return true end
	if raidKind then
		local assist = RPL.Set( f.assist )
		for _, e in ipairs( st.list ) do
			if ( e.assist and true or false ) ~= ( assist[ e.name ] and true or false ) then return true end
			if ( e.loot and true or false ) ~= ( f.loot == e.name ) then return true end
		end
	end
	return false
end

-- Запись для сохранения: только живые участники, места — в порядке отображения
-- Игроки с других серверов и из других фракций не сохраняются (возвращается их число)
function V.BuildRecord( st, m )
	local leaderE = st.leader and st.byName[ st.leader ]
	local rec = { kind = st.kind, members = {}, assist = {}, leader = ( leaderE and not leaderE.foreign ) and st.leader or nil,
		lootScheme = st.lootScheme, lootQuality = st.lootQuality }
	local skipped = 0
	for g = 1, m.ng do
		local s = 0
		for _, e in ipairs( m.groups[ g ] ) do
			if e.live and e.foreign then skipped = skipped + 1 end
			if e.live and not e.foreign then
				s = s + 1
				table.insert( rec.members, { n = e.name, g = g, s = s } )
				if e.assist then table.insert( rec.assist, e.name ) end
				if e.loot then rec.loot = e.name end
			end
		end
	end
	return rec, skipped
end

--------------------------------------------------------------------------------
-- Слоты
--------------------------------------------------------------------------------
local function HideRight( slot, except )
	for _, n in ipairs( RIGHT_BUTTONS ) do RPL.Show( slot[ n ], n == except ) end
end

local function RenderEmptySlot( slot, moveTarget )
	RPL.SetVariant( slot.SlotButton, moveTarget and VAR_TARGET or VAR_EMPTY )
	for _, n in ipairs( { "ClassIcon", "LeaderBadge", "AssistBadge", "LootBadge", "FactionBadge", "AspectIcon", "StatusIcon" } ) do
		RPL.Show( slot[ n ], false )
	end
	RPL.SetText( slot.NameText, "" )
	HideRight( slot, nil )
end

local function RenderBadges( slot, e )
	RPL.Show( slot.LeaderBadge, e.leader )
	RPL.Show( slot.AssistBadge, e.assist and not e.leader )
	RPL.Show( slot.LootBadge, e.loot )
end

local function RenderCurrentSlot( slot, e, ctx )
	local st = ctx.st
	local selected = ( ctx.sel ~= nil and ctx.sel.name == e.name )
	local off = e.misplaced or e.misordered
	RPL.SetVariant( slot.SlotButton, selected and VAR_SELECTED or ( off and VAR_MISPLACED ) or VAR_NORMAL )
	-- межсерверное формирование: у игроков с чужого сервера — метка сервера после ника
	local shown = e.name
	if st.crossShard and e.shard and e.shard ~= st.myShard then shown = e.name .. " · " .. RPL.Game.ShardTag( e.shard ) end
	RPL.SetText( slot.NameText, shown )
	if e.pending then
		RPL.Show( slot.ClassIcon, RPL.SetTex( slot.ClassIcon, "Classes", e.cls or "UNKNOWN" ) )
		RPL.Show( slot.AspectIcon, false )
		RPL.Show( slot.FactionBadge, false )
		RenderBadges( slot, {} )
		-- статусов приглашений нет: у недостающего справа кнопка «+»
		RPL.Show( slot.StatusIcon, false )
	else
		RPL.Show( slot.ClassIcon, RPL.SetTex( slot.ClassIcon, "Classes", e.cls or "UNKNOWN" ) )
		RPL.Show( slot.AspectIcon, e.asp and RPL.SetTex( slot.AspectIcon, "Aspects", e.asp ) )
		RenderBadges( slot, e )
		-- межфракционное формирование: значок фракции у всех; межсерверное: метка чужого сервера
		local facTex = st.crossFaction and e.fac and ( FAC_TEX[ e.fac ] or "FAC_OTHER" ) or nil
		RPL.Show( slot.FactionBadge, facTex and RPL.SetTex( slot.FactionBadge, "Icons", facTex ) )

		local icon = ( e.ready and READY_ICON[ e.ready ] ) or ( e.offline and "OFFLINE" ) or ( e.stranger and "STRANGER" )
			or ( off and "MISPLACED" ) or nil
		RPL.Show( slot.StatusIcon, icon and RPL.SetTex( slot.StatusIcon, "Icons", icon ) )
	end
	-- одна кнопка справа на карточке
	local right = nil
	local sel = ctx.sel
	-- обмен — в отряде, между любыми двумя участниками (raid.SwapMembers)
	if sel and e.live and e.name ~= sel.name and st.canManage and RPL.IsRaidKind( st.kind ) then
		right = "SwapButton"
	elseif e.pending and ( st.kind == "none" or st.canInvite ) then
		right = "RetryButton"
	elseif off and st.canManage and not sel then
		right = "HomeButton"
	elseif selected and st.kind == "party" and st.isLeader and e.name ~= st.me then
		right = "KickButton"
	end
	HideRight( slot, right )
end

local function RenderDetailSlot( slot, e )
	RPL.SetVariant( slot.SlotButton, VAR_NORMAL )
	RPL.SetText( slot.NameText, e.name )
	RPL.Show( slot.ClassIcon, false )
	RPL.Show( slot.AspectIcon, false )
	RPL.Show( slot.StatusIcon, false )
	RPL.Show( slot.FactionBadge, false )
	RenderBadges( slot, e )
	HideRight( slot, nil )
end

local function RenderGroups( m, mode, ctx )
	for g = 1, 4 do
		local grp = ui.groups[ g ]
		local visible = g <= m.ng
		RPL.Show( grp.w, visible )
		if visible then
			local list = m.groups[ g ]
			local live = 0
			for _, e in ipairs( list ) do
				if e.live or e.saved then live = live + 1 end
			end
			RPL.SetLabel( grp.header, RPL.F( RPL.L.groupTitle, g ) )
			RPL.SetText( grp.count, RPL.F( "%d/%d", live, RPL.GROUP_SIZE ) )
			for k = 1, RPL.GROUP_SIZE do
				local slot = grp.slots[ k ]
				local e = list[ k ]
				if not e then
					local moveTarget = mode == "current" and ctx.sel and ctx.st.canManage
						and RPL.Game.CanMoveTo( ctx.st, ctx.sel, g )
					RenderEmptySlot( slot, moveTarget )
				elseif mode == "current" then
					RenderCurrentSlot( slot, e, ctx )
				else
					RenderDetailSlot( slot, e )
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Экраны
--------------------------------------------------------------------------------
-- Правый отступ (highPosX) для виджета с привязкой BOTH
local highX = {}
local function SetHighX( w, hx )
	if not w or highX[ w ] == hx then return end
	highX[ w ] = hx
	local p = w:GetPlacementPlain()
	p.highPosX = hx
	w:SetPlacementPlain( p )
end

-- Строка «Дележ / Ценность». mode: "current" — живые значения игры, "detail" — сохранённые
function V.RenderLootBar( mode )
	local bar = RPL.W( "LootBar" )
	if not mode then RPL.Show( bar, false ) return end
	RPL.Show( bar, true )
	local scheme, quality, enabled
	if mode == "current" then
		local st, f = RPL.st, RPL.model and RPL.model.f
		if st.kind ~= "none" then
			scheme, quality, enabled = st.lootScheme, st.lootQuality, st.canLoot
		else
			scheme, quality, enabled = f and f.lootScheme, f and f.lootQuality, false
		end
	else
		local f = V.DetailF()
		scheme, quality, enabled = f and f.lootScheme, f and f.lootQuality, f ~= nil
	end
	local s, q = RPL.Scheme( scheme ), RPL.Quality( quality )
	RPL.SetLabel( RPL.W( "LootSchemeButton" ), s and s.label or "—" )
	RPL.SetLabel( RPL.W( "LootQualityButton" ), "     " .. ( q and q.label or "—" ) )
	local dot = RPL.W( "LootQualityDot" )
	RPL.Show( dot, q and RPL.SetTex( dot, "Icons", "Q_" .. q.key ) )
	RPL.Enable( RPL.W( "LootSchemeButton" ), enabled )
	RPL.Enable( RPL.W( "LootQualityButton" ), enabled )
end

local posX = {}
local function SetPosX( w, x )
	if not w or posX[ w ] == x then return end
	posX[ w ] = x
	local p = w:GetPlacementPlain()
	p.posX = x
	w:SetPlacementPlain( p )
end

local posY = {}
local function SetPosY( w, y )
	if not w or posY[ w ] == y then return end
	posY[ w ] = y
	local p = w:GetPlacementPlain()
	p.posY = y
	w:SetPlacementPlain( p )
end

local function RenderModeChip( st )
	local kind = st.kind
	local cap = RPL.KindGroups( kind ) * RPL.GROUP_SIZE
	if kind == "none" then
		RPL.SetText( RPL.W( "ModeText" ), ( RPL.asm and RPL.asm.active ) and RPL.L.kindNoneAsm or RPL.L.kindNone )
	else
		RPL.SetText( RPL.W( "ModeText" ), RPL.F( RPL.L.modeChip, RPL.KindLabel( kind ), #st.list, cap ) )
	end
end

local function RenderCurrent()
	local m = RPL.model
	local st, f = m.st, m.f
	local empty = ( st.kind == "none" and not f )
	RPL.Show( RPL.W( "EmptyView" ), empty )
	RPL.Show( RPL.W( "CurrentView" ), not empty )
	RPL.Show( ui.groupsPanel, not empty )
	if empty then return end

	local kind = ( st.kind ~= "none" ) and st.kind or f.kind
	local raidKind = RPL.IsRaidKind( kind )

	-- связь: сохранённое, снимок из «Быстрого» (не сохранено) или ничего (неизвестный состав)
	local quick = ( RPL.link == RPL.Store.QUICK )
	local saved = f ~= nil and not quick
	local summary = f and V.DiffSummary( f, st )
	-- перестановки (другая группа или другой порядок в группе) — тоже изменение: можно «Обновить»
	local differs = summary ~= nil or #m.misplaced > 0 or #m.misordered > 0
	RPL.Show( RPL.W( "LinkIcon" ), f ~= nil )
	local title = ( saved and f.name ) or ( quick and RPL.F( RPL.L.linkQuick, f.name ) )
		or ( raidKind and RPL.L.currentRaid or RPL.L.currentParty )
	RPL.SetText( RPL.W( "LinkTitle" ), title )
	local stateText = f and ( summary or "" ) or RPL.L.notSaved
	-- кому не хватило места из-за «не из состава» — последние по местам
	if #m.overflow > 0 then
		local o = RPL.F( RPL.L.diffOverflow, table.concat( m.overflow, ", " ) )
		stateText = ( stateText ~= "" ) and ( stateText .. " · " .. o ) or o
	end
	RPL.SetText( RPL.W( "LinkState" ), stateText )
	-- нет второй строки — название по центру панели, без пустоты под ним
	SetPosY( RPL.W( "LinkTitle" ), RPL.Px( stateText == "" and 14 or 6 ) )
	local canUpdate = saved and differs and st.kind ~= "none"
	local canSave = not saved
	-- текст занимает всё место до видимых кнопок справа
	local P = RPL.Px
	local reserve = canUpdate and ( P( 175 ) + P( 90 ) + P( 8 ) ) or ( canSave and ( P( 7 ) + P( 140 ) + P( 8 ) ) ) or P( 7 )
	-- выбор сохранённого вручную (вступил в чужой отряд, собрал руками) — левее кнопок
	local pick = RPL.W( "LinkPickButton" )
	local canPick = st.kind ~= "none" or f ~= nil
	RPL.Show( pick, canPick )
	if canPick then
		SetHighX( pick, reserve )
		reserve = reserve + P( 32 ) + P( 8 )
	end
	SetHighX( RPL.W( "LinkTitle" ), reserve )
	SetHighX( RPL.W( "LinkState" ), reserve )
	RPL.Show( RPL.W( "UpdateButton" ), canUpdate )
	RPL.Show( RPL.W( "SaveAsNewButton" ), canUpdate )
	local save = RPL.W( "SaveButton" )
	RPL.Show( save, canSave )
	RPL.SetLabel( save, raidKind and RPL.L.saveRaid or RPL.L.saveParty )
	RPL.Enable( save, st.kind ~= "none" )
	RPL.Show( RPL.W( "InfoText" ), false )

	-- действия: «Пригласить всех» — пока кого-то не хватает. Вне группы позовёт первого
	-- по местам, в группе для отряда — сначала превратит её, остальных позовёт сам.
	-- Число — сколько реально позовёт: на чужие места не рассчитываем.
	local inviteAll = RPL.W( "InviteAllButton" )
	local showInviteAll = f ~= nil and #m.pending > 0
	RPL.Show( inviteAll, showInviteAll )
	RPL.SetLabel( inviteAll, RPL.F( RPL.L.inviteAll, m.invitable ) )
	RPL.Enable( inviteAll, m.invitable > 0 and st.canInvite and not RPL.KindBlocked( st.kind, f and f.kind ) )
	local placeAll = RPL.W( "PlaceAllButton" )
	-- «Расставить» встаёт к левому краю, когда «Пригласить всех» скрыта
	SetPosX( placeAll, showInviteAll and RPL.Px( 172 ) or 0 )
	local offCount = #m.misplaced + #m.misordered
	RPL.Show( placeAll, offCount > 0 )
	RPL.SetLabel( placeAll, RPL.F( RPL.L.placeAll, offCount ) )
	RPL.Enable( placeAll, st.canManage )

	local sel = RPL.sel and st.byName[ RPL.sel ] or nil
	local inRaid = RPL.IsRaidKind( st.kind )
	-- роли и исключение — только лидер (помощник может приглашать и переставлять)
	local canAct = sel ~= nil and st.isLeader and inRaid
	for _, n in ipairs( { "AssistButton", "LootButton", "KickSelButton" } ) do
		RPL.Show( RPL.W( n ), inRaid )
	end
	-- лидеру помощник не нужен: у него и так все права.
	-- «Лидер — ответственный за добычу» = снять ответственного: тогда добычу распределяет лидер.
	local otherLoot = false
	for _, e in ipairs( st.list ) do
		if e.loot and not e.leader then otherLoot = true end
	end
	RPL.Enable( RPL.W( "AssistButton" ), canAct and not sel.leader )
	RPL.Enable( RPL.W( "LootButton" ), canAct and ( not sel.leader or otherLoot ) )
	RPL.Enable( RPL.W( "KickSelButton" ), canAct and sel.name ~= st.me and not sel.leader )
	-- передача лидерства и проверка готовности — рядом с ролями.
	-- В группе кнопок ролей нет: эти две встают к правому краю.
	local P = RPL.Px
	local lead = RPL.W( "LeaderButton" )
	RPL.Show( lead, st.kind ~= "none" )
	SetHighX( lead, inRaid and P( 120 ) or 0 )
	RPL.Enable( lead, sel ~= nil and st.isLeader and sel.name ~= st.me and sel.live and not sel.offline )
	local ready = RPL.W( "ReadyButton" )
	RPL.Show( ready, st.kind ~= "none" )
	SetHighX( ready, inRaid and P( 160 ) or P( 40 ) )
	RPL.Enable( ready, st.canReady and not st.readyActive )

	-- нижняя строка
	RPL.Enable( RPL.W( "InviteButton" ), st.canInvite )

	RenderGroups( m, "current", { st = st, sel = sel } )
end

local savedRows = {}

function V.RenderSaved()
	local list = RPL.W( "SavedList" )
	local tpl = RPL.W( "SavedRow" )
	if not list or not tpl then return end
	list:RemoveItems()
	for _, row in ipairs( savedRows ) do row:DestroyWidget() end
	savedRows = {}
	local items = RPL.Store.List()
	RPL.Show( RPL.W( "NoSavedText" ), #items == 0 )
	local desc = tpl:GetWidgetDesc()
	for _, f in ipairs( items ) do
		-- строки создаются заново, поэтому без кэша значений: прямые вызовы
		local row = mainForm:CreateChildByDesc( desc )
		row:SetName( "Row" .. f.id )
		RPL.Child( row, "RowKindParty" ):Show( f.kind == "party" )
		RPL.Child( row, "RowKindRaid" ):Show( f.kind == "raid" )
		RPL.Child( row, "RowKindSmall" ):Show( f.kind == "small" )
		RPL.Child( row, "RowName" ):SetVal( "value", RPL.WS( f.name ) )
		RPL.Child( row, "RowMeta" ):SetVal( "value", RPL.WS( RPL.F( RPL.L.members, #( f.members or {} ) ) ) )
		row:Show( true )
		list:PushBack( row )
		savedRows[ #savedRows + 1 ] = row
	end
	RPL.savedDirty = false
end

-- Формирование на экране карточки: сохранённое (вкладка «Сохранённые») или из «Быстрого».
-- Второе значение — ключ, под которым его собирают и связывают (id или Store.QUICK).
function V.DetailF()
	if RPL.tab == "quick" then
		local key = RPL.Store.QuickKey()
		return RPL.Store.Get( key ), key
	end
	return RPL.Store.Get( RPL.detailId ), RPL.detailId
end

-- Можно ли сейчас собирать f с этого экрана. Нет — текст причины.
-- Вне группы — можно. В группе — только если «Текущее» уже связано именно с ним
-- (иначе это чужой или другой состав: выбрать скрепкой или выйти).
function V.CanAssemble( st, f, key )
	if st.kind == "none" then return true end
	if RPL.link ~= key then
		local cur = RPL.Store.Get( RPL.link )
		if cur and RPL.link ~= RPL.Store.QUICK then return false, RPL.F( RPL.L.noteOther, cur.name ) end
		if cur then return false, RPL.F( RPL.L.noteOther, RPL.F( RPL.L.linkQuick, cur.name ) ) end
		return false, RPL.L.noteUnknown
	end
	if RPL.KindBlocked( st.kind, f.kind ) then
		return false, RPL.F( RPL.L.noteKind, RPL.L.kindIn[ st.kind ] or "", RPL.L.kindTo[ f.kind ] or "" )
	end
	if not st.canInvite then return false, RPL.L.noteNotLeader end
	return true
end

local function RenderDetail()
	local f, key = V.DetailF()
	local quick = RPL.tab == "quick"
	RPL.Show( RPL.W( "DetailView" ), f ~= nil )
	RPL.Show( RPL.W( "QuickEmptyView" ), quick and f == nil )
	if not f then
		RPL.Show( ui.groupsPanel, false )
		if not quick then
			RPL.tab = "saved"
			RPL.savedDirty = true
			return V.Render()
		end
		return
	end
	local st = RPL.st
	local m = V.BuildDetail( f, st )
	local snap = quick and key == RPL.Store.QUICK
	local P = RPL.Px
	-- шапка: в «Быстром» нет «назад», зато есть «Сохранить» (у снимка) и «Удалить»
	RPL.Show( RPL.W( "BackButton" ), not quick )
	RPL.Show( RPL.W( "QuickSaveButton" ), snap )
	RPL.Show( RPL.W( "QuickDeleteButton" ), quick )
	local left = quick and P( 14 ) or P( 52 )
	local right = ( snap and P( 230 ) ) or ( quick and P( 122 ) ) or P( 90 )
	for _, n in ipairs( { "DetailTitle", "DetailMeta" } ) do
		SetPosX( RPL.W( n ), left )
		SetHighX( RPL.W( n ), right )
	end
	RPL.SetText( RPL.W( "DetailTitle" ), f.name )
	local n = #( f.members or {} )
	RPL.SetText( RPL.W( "DetailMeta" ), ( snap and RPL.F( RPL.L.quickMetaSnap, n ) )
		or ( quick and RPL.F( RPL.L.quickMetaRef, n ) ) or RPL.F( RPL.L.members, n ) )
	RPL.Show( RPL.W( "DetailKindParty" ), f.kind == "party" )
	RPL.Show( RPL.W( "DetailKindRaid" ), f.kind == "raid" )
	RPL.Show( RPL.W( "DetailKindSmall" ), f.kind == "small" )
	local start = RPL.W( "StartInviteButton" )
	RPL.SetLabel( start, RPL.F( RPL.L.inviteAll, m.invitable ) )
	local ok, why = V.CanAssemble( st, f, key )
	RPL.Enable( start, ok and m.invitable > 0 )
	RPL.SetText( RPL.W( "InviteNote" ), why or "" )
	RPL.Show( ui.groupsPanel, true )
	RenderGroups( m, "detail", {} )
end

-- Индикатор на кнопке RPL:
--   OK   (зелёный) — в группе/отряде, совпадает с сохранённым, все на местах;
--   WARN (жёлтый)  — идёт сбор, или есть отличия от сохранённого / не на местах;
--   BAD  (красный) — в группе/отряде, который не сохранён;
--   нет            — не в группе и сбор не идёт.
function V.RenderBadge( st, m )
	local state = nil
	if RPL.asm and RPL.asm.active then
		state = "WARN"
	elseif st.kind ~= "none" then
		if not m.f then
			state = "BAD"
		elseif m.badge or V.DiffSummary( m.f, st ) ~= nil then
			state = "WARN"
		else
			state = "OK"
		end
	end
	local w = RPL.W( "RPLBadge" )
	RPL.Show( w, state ~= nil and RPL.SetTex( w, "Icons", "DOT_" .. tostring( state ) ) )
end

-- Ширина окна как в прототипе: max(470, 14 + колонки по 206 с шагом 214 + 14), с масштабом.
-- Группы растягиваются на всю ширину (в прототипе grid repeat(cols, 1fr)), поэтому
-- в узком окне группа шире 206 и правые края групп совпадают с кнопками над ними.
local currentCols = nil
local function SetWindowWidth( cols )
	if cols == currentCols then return end
	currentCols = cols
	local P = RPL.Px
	-- в отряде окно чуть шире: в нижнем ряду слева «Пригласить всех» и «Расставить»,
	-- справа готовность и роли — им нужно не пересекаться
	local w = math.max( P( cols > 1 and 540 or 470 ), 2 * P( 14 ) + P( ( cols - 1 ) * 214 ) + P( 206 ) )
	local p = ui.window:GetPlacementPlain()
	p.sizeX = w
	ui.window:SetPlacementPlain( p )
	local gap = P( 8 )
	local gw = math.floor( ( w - 2 * P( 14 ) - ( cols - 1 ) * gap ) / cols )
	for g = 1, 4 do
		local gp = ui.groups[ g ].w:GetPlacementPlain()
		gp.posX = ( g - 1 ) * ( gw + gap )
		gp.sizeX = gw
		ui.groups[ g ].w:SetPlacementPlain( gp )
	end
end

function V.Render()
	local st = RPL.st
	if not st or not ui.window then return end
	RPL.model = V.BuildCurrent( st )
	V.RenderBadge( st, RPL.model )
	if not ui.window:IsVisible() then return end

	local tab = RPL.tab
	local cols = 1
	if tab == "current" and not ( st.kind == "none" and not RPL.model.f ) then
		cols = math.max( 1, RPL.model.ng )
	elseif tab == "detail" or tab == "quick" then
		local f = V.DetailF()
		cols = f and RPL.KindGroups( f.kind ) or 1
	end
	SetWindowWidth( cols )
	RPL.Show( RPL.W( "TabCurrentLine" ), tab == "current" )
	RPL.Show( RPL.W( "TabSavedLine" ), tab == "saved" or tab == "detail" )
	RPL.Show( RPL.W( "TabQuickLine" ), tab == "quick" )
	RenderModeChip( st )

	RPL.Show( RPL.W( "SavedView" ), tab == "saved" )
	if tab ~= "detail" and tab ~= "quick" then
		RPL.Show( RPL.W( "DetailView" ), false )
		RPL.Show( RPL.W( "QuickEmptyView" ), false )
	end
	if tab ~= "current" then
		RPL.Show( RPL.W( "CurrentView" ), false )
		RPL.Show( RPL.W( "EmptyView" ), false )
	end

	if tab == "current" then
		RenderCurrent()
		V.RenderLootBar( not ( st.kind == "none" and not RPL.model.f ) and "current" or nil )
	elseif tab == "saved" then
		RPL.Show( ui.groupsPanel, false )
		V.RenderLootBar( nil )
		if RPL.savedDirty then V.RenderSaved() end
	else
		RenderDetail()
		V.RenderLootBar( V.DetailF() and "detail" or nil )
	end
end
