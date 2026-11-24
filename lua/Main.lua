--------------------------------------------------------------------------------
-- RaidPartyLeader / Main.lua
-- Состояние, сбор формирования, обработчики событий и реакций.
--------------------------------------------------------------------------------
local G, V, Store = RPL.Game, RPL.View, RPL.Store

RPL.tab = "current"      -- "current" | "saved" | "detail" | "quick"
RPL.sel = nil            -- имя выбранного участника
RPL.link = nil           -- с чем связан текущий состав: id сохранённого или Store.QUICK (снимок)
RPL.detailId = nil
RPL.order = {}           -- визуальный порядок внутри группы: [ник] = число
RPL.asm = nil            -- сбор: { active, roles = {}, convertAt, raidSince, inviteRestAt, lootTry, rolesManual, lootManual }
RPL.placing = 0          -- сколько секунд ещё расставлять по местам
RPL.readyShow = false    -- показывать ли на карточках результат проверки готовности
RPL.readyUntil = nil     -- до какого тика (после окончания проверки)
RPL.dialog = nil         -- { mode = "new" | "copy" | "rename", id }
RPL.savedDirty = true
RPL.st = nil
RPL.model = nil

local started = false
local prevKind = "none"
local wasInGroup, noneSince = false, nil -- для сброса связи после роспуска
local firstTurn = 0 -- сбор отряда вне группы: кого по порядку мест звали последним

--------------------------------------------------------------------------------
-- Темп операций с отрядом. Если слать перенос и права пачкой, сервер обрабатывает
-- не все. Поэтому автоматические операции (расстановка, выдача ролей) идут по одной:
-- следующая — после события об изменении отряда или через 2 секунды.
--------------------------------------------------------------------------------
local pace = { waiting = false, untilTick = 0 }

local function CanAct()
	return not pace.waiting or RPL.tick >= pace.untilTick
end

local function Acted()
	pace.waiting = true
	pace.untilTick = RPL.tick + 2
end

local PlaceStep -- объявлена ниже, в разделе «Расстановка»
local InviteMissing -- объявлена ниже, в разделе «Приглашения и сбор»

--------------------------------------------------------------------------------
-- Обновление
--------------------------------------------------------------------------------
local function SyncAssembly( st, f )
	local asm = RPL.asm
	if not asm then return end
	-- сбор идёт, пока не пришли ВСЕ участники формирования
	local left = 0
	for _, t in ipairs( f and f.members or {} ) do
		if t.n ~= st.me and not st.byName[ t.n ] then left = left + 1 end
	end
	-- группа стала отрядом: роли выдаём не сразу, а через пару секунд (RoleStep).
	-- Как SaveRaid: отряд появился — один раз зовём всех остальных (через секунду, когда
	-- отряд уже принимает приглашения). Дальше — «Пригласить всех» / Shift+ПКМ.
	if RPL.IsRaidKind( st.kind ) and not RPL.IsRaidKind( prevKind ) then
		asm.raidSince = RPL.tick
		if asm.active and prevKind == "party" and left > 0 then asm.inviteRestAt = RPL.tick + 1 end
	end
	-- собрано, когда все пришли И тип совпал (группа уже стала отрядом нужного вида):
	-- расставляем по местам; роли и дележ выставят RoleStep / LootStep
	local kindReady = not f or f.kind == st.kind
	if left == 0 and kindReady and asm.active then
		asm.active = false
		asm.inviteRestAt = nil
		local m = V.BuildCurrent( st )
		local off = #m.misplaced + #m.misordered
		if off > 0 and st.canManage and RPL.IsRaidKind( st.kind ) then
			RPL.placing = 30
			RPL.Toast( RPL.L.toastAssembledPlace )
		else
			RPL.Toast( RPL.L.toastAssembled )
		end
	end
end

-- Роли из сохранённого формирования: одна операция за раз (см. темп),
-- повтор раз в 2 секунды, пока роль не появится, не больше ROLE_TRIES раз.
local ROLE_TRIES = 5

local function RoleStep( st, f )
	local asm = RPL.asm
	if not asm or not f or not RPL.IsRaidKind( st.kind ) or not st.isLeader then return false end
	if asm.rolesManual then return false end -- роли меняли руками: больше не вмешиваемся
	if not asm.raidSince or RPL.tick - asm.raidSince < 2 then return false end -- отряд только что создан
	local assist = RPL.Set( f.assist )
	for _, e in ipairs( st.list ) do
		if e.uid and not e.leader then
			local r = asm.roles[ e.name ]
			if not r then
				r = { assist = 0, loot = 0, t = -10 }
				asm.roles[ e.name ] = r
			end
			-- роль, которая хоть раз появилась, считается выданной: дальше игрока не трогаем
			if assist[ e.name ] and e.assist then r.assistDone = true end
			if f.loot == e.name and e.loot then r.lootDone = true end
			local needAssist = assist[ e.name ] and not e.assist and not r.assistDone
			local needLoot = f.loot == e.name and not e.loot and not r.lootDone
			if ( needAssist and r.assist >= ROLE_TRIES ) or ( needLoot and r.loot >= ROLE_TRIES ) then
				if not r.warned then
					r.warned = true
					RPL.Warn( "не удалось выдать роль:", e.name )
				end
			end
			if RPL.tick - r.t >= 2 then
				if needAssist and r.assist < ROLE_TRIES then
					r.assist, r.t = r.assist + 1, RPL.tick
					G.GiveAssist( e )
					RPL.Log( "роль: помощник ->", e.name, "попытка", r.assist ) --@debug
					return true
				end
				if needLoot and r.loot < ROLE_TRIES then
					r.loot, r.t = r.loot + 1, RPL.tick
					G.GiveLoot( e )
					RPL.Log( "роль: добыча ->", e.name, "попытка", r.loot ) --@debug
					return true
				end
			end
		end
	end
	return false
end

-- Дележ и ценность из сохранённого: после того как тип формирования совпал,
-- сначала схема, потом порог (он действует для текущей схемы). Одна операция за раз.
local LOOT_TRIES = 5

local function LootStep( st, f )
	local asm = RPL.asm
	if not asm or not f or not st.canLoot or asm.lootManual then return false end
	if st.kind == "none" or f.kind ~= st.kind then return false end
	if RPL.IsRaidKind( st.kind ) and ( not asm.raidSince or RPL.tick - asm.raidSince < 2 ) then return false end
	asm.lootTry = asm.lootTry or { scheme = 0, quality = 0, t = -10 }
	local r = asm.lootTry
	if f.lootScheme and st.lootScheme == f.lootScheme then r.schemeDone = true end
	if f.lootQuality and st.lootQuality == f.lootQuality then r.qualityDone = true end
	if RPL.tick - r.t < 2 then return false end
	if f.lootScheme and not r.schemeDone and st.lootScheme ~= f.lootScheme and r.scheme < LOOT_TRIES then
		r.scheme, r.t = r.scheme + 1, RPL.tick
		G.SetLootScheme( f.lootScheme )
		RPL.Log( "дележ ->", f.lootScheme, "попытка", r.scheme ) --@debug
		return true
	end
	if f.lootQuality and not r.qualityDone and st.lootQuality ~= f.lootQuality and r.quality < LOOT_TRIES then
		r.quality, r.t = r.quality + 1, RPL.tick
		G.SetLootQuality( f.lootQuality )
		RPL.Log( "ценность ->", f.lootQuality, "попытка", r.quality ) --@debug
		return true
	end
	return false
end

local function MaybeConvert( st, f )
	local asm = RPL.asm
	if not asm or not asm.active or not f or not RPL.IsRaidKind( f.kind ) then return end
	if st.kind ~= "party" or not st.isLeader or #st.list < 2 then return end
	if asm.convertAt and RPL.tick - asm.convertAt < 3 then return end
	asm.convertAt = RPL.tick
	G.Convert( f.kind )
end

local function ResetLink()
	RPL.link = nil
	Store.SetLink( nil )
	RPL.asm = nil
	firstTurn = 0
	RPL.placing = 0
	RPL.order = {}
	RPL.sel = nil
end

function RPL.Refresh()
	if not started then return end
	-- состав читаем всегда: от него зависит цвет индикатора на кнопке.
	-- Пока окно закрыто, аспекты не читаем — они нужны только для карточек.
	local st = G.Read( not V.ui.window:IsVisible() )
	RPL.st = st
	-- «Текущее» — это реальное состояние: группу или отряд распустили — связь и сбор
	-- сбрасываются. Собрать заново — из «Сохранённых», «Пригласить всех».
	-- Ждём 2 секунды: при превращении группы в отряд может быть момент «ни того, ни другого».
	if st.kind ~= "none" then
		wasInGroup, noneSince = true, nil
		firstTurn = 0
	elseif wasInGroup then
		noneSince = noneSince or RPL.tick
		if RPL.tick - noneSince >= 2 then
			RPL.Log( "вышли из формирования: связь сброшена" ) --@debug
			ResetLink()
			wasInGroup, noneSince = false, nil
		end
	end
	if RPL.sel and not st.byName[ RPL.sel ] then RPL.sel = nil end
	if RPL.link and not Store.Get( RPL.link ) then ResetLink() end
	-- Связь — только действием игрока (сбор, скрепка, ПКМ), никакого угадывания.
	-- Собирали вне группы, а вступили в чужое формирование (наши приглашения у людей
	-- теперь недействительны): мы не лидер и никого из собираемого рядом нет — сбор отменён.
	if prevKind == "none" and st.kind ~= "none" and RPL.asm and RPL.asm.active and not st.isLeader then
		local target = V.Target( Store.Get( RPL.link ) )
		local ours = false
		for _, e in ipairs( st.list ) do
			if e.name ~= st.me and target[ e.name ] then ours = true break end
		end
		if not ours then
			ResetLink()
			RPL.Toast( RPL.L.toastForeignInvite )
		end
	end
	if st.kind ~= "none" then Store.SetLink( RPL.link ) end
	local f = Store.Get( RPL.link )
	SyncAssembly( st, f )
	MaybeConvert( st, f )
	-- отряд появился (после приглашения первого) — один раз зовём остальных
	local asm = RPL.asm
	if asm and asm.active and asm.inviteRestAt and RPL.tick >= asm.inviteRestAt then
		asm.inviteRestAt = nil
		-- Ожидаем: отряд не наш (первый по местам сам позвал нас к себе) и приглашать
		-- нам нельзя — остальных не зовём
		if st.canInvite then InviteMissing( f ) end
	end
	prevKind = st.kind
	V.Render()
	-- одна автоматическая операция за раз
	if CanAct() then
		local acted = false
		if RPL.placing > 0 then
			if RPL.model and #RPL.model.misplaced == 0 and #RPL.model.misordered == 0 then
				RPL.placing = 0
				RPL.Toast( RPL.L.toastPlaced )
			else
				acted = PlaceStep()
			end
		end
		if not acted then acted = RoleStep( st, f ) end
		if not acted then acted = LootStep( st, f ) end
		if acted then Acted() end
	end
end

--------------------------------------------------------------------------------
-- Приглашения и сбор
-- Автоповторов и статусов приглашений нет: API не даёт надёжно понять, чем кончилось
-- приглашение (отказ «запретная территория» в отряд приходит без ника, об истечении
-- приглашения событий нет вовсе). У недостающих — кнопка «+», внизу — «Пригласить всех»,
-- на кнопке RPL — Shift+ПКМ. Решает лидер.
--------------------------------------------------------------------------------
local function EnsureAsm()
	RPL.asm = RPL.asm or { roles = {} }
	RPL.asm.active = true
	-- сбор начат уже в отряде: роли можно выдавать сразу
	if RPL.st and RPL.IsRaidKind( RPL.st.kind ) and not RPL.asm.raidSince then RPL.asm.raidSince = RPL.tick - 10 end
	return RPL.asm
end

function RPL.InviteNow( name )
	G.Invite( name ) -- в отряд, если он есть, иначе в группу
	RPL.Log( "приглашение:", name ) --@debug
end

-- Недостающие участники формирования в порядке мест: группа, затем место
local function Missing( st, f )
	local list = {}
	for _, t in ipairs( f.members or {} ) do
		if t.n ~= st.me and not st.byName[ t.n ] then list[ #list + 1 ] = t end
	end
	table.sort( list, function( x, y )
		if x.g ~= y.g then return x.g < y.g end
		return x.s < y.s
	end )
	return list
end

-- Позвать недостающих f:
--   вне группы: группа — всех; отряд — одного: сначала первого по местам, при каждом
--     следующем нажатии — следующего (первый может быть не в сети, а узнать это вне группы
--     нельзя). Приглашения в группу пачкой повисли бы открытыми, когда она станет отрядом.
--     Кто примет — группа станет отрядом
--     (MaybeConvert), и остальных аддон позовёт сам один раз (SyncAssembly, inviteRestAt);
--   в группе, а собираем отряд: сначала превращаем группу, остальных — когда отряд появится;
--   иначе: всех, сколько помещается. Места считаются по всем в составе, и по
--     «не из состава» тоже: по порядку мест последние не помещаются.
InviteMissing = function( f )
	local st = RPL.st
	if not f or not st then return 0 end
	EnsureAsm()
	local list = Missing( st, f )
	if st.kind == "none" and RPL.IsRaidKind( f.kind ) then
		if #list == 0 then return 0 end
		firstTurn = firstTurn % #list + 1
		RPL.InviteNow( list[ firstTurn ].n )
		return 1
	end
	if st.kind == "party" and RPL.IsRaidKind( f.kind ) and #st.list >= 2 then
		RPL.asm.convertAt = nil
		MaybeConvert( st, f )
		return 0
	end
	local free = V.FreeSlots( st, f )
	local n = 0
	for _, t in ipairs( list ) do
		if n >= free then break end
		RPL.InviteNow( t.n )
		n = n + 1
	end
	return n
end

local function InviteOne( name )
	EnsureAsm()
	RPL.InviteNow( name )
end

-- Собрать формирование key (id сохранённого или Store.QUICK) или привести его в боевую
-- готовность, если мы уже в нём: позвать недостающих, а когда пришли все — расставить,
-- выдать роли и дележ (SyncAssembly, RoleStep, LootStep). fresh — заново выдать роли и
-- дележ, даже если их меняли руками (Shift+ПКМ — явная команда «как в сохранённом»).
local function Assemble( key, fresh )
	local f = Store.Get( key )
	local st = RPL.st
	if not f or not st then return end
	if RPL.KindBlocked( st.kind, f.kind ) then
		RPL.Toast( RPL.F( RPL.L.noteKind, RPL.L.kindIn[ st.kind ] or "", RPL.L.kindTo[ f.kind ] or "" ) )
		return
	end
	-- Ожидаем: вне группы, а в формировании только мы сами — звать некого, сбор не начинаем
	-- (иначе он висел бы «идёт сбор» без конца)
	if st.kind == "none" and #Missing( st, f ) == 0 then return end
	if RPL.link ~= key then firstTurn = 0 end
	if RPL.link ~= key or fresh then
		RPL.order = {}
		RPL.asm = nil
	end
	RPL.link = key
	Store.SetLink( key )
	-- сбор вне группы: связь держится, пока кто-нибудь не примет приглашение
	if st.kind == "none" then wasInGroup, noneSince = false, nil end
	EnsureAsm()
	InviteMissing( f )
end

--------------------------------------------------------------------------------
-- Расстановка
--------------------------------------------------------------------------------
-- Один шаг = одна операция; следующий — после ответа сервера (см. темп).
-- Группы идут без пропусков, поэтому перенос, который невозможен (группа полна,
-- игрок последний в группе и уходит дальше, нужная группа ещё не появилась),
-- заменяем обменом с тем, кто стоит в целевой группе не на своём месте.
-- Если сейчас сделать ничего нельзя, ждём: другие переносы могут это открыть.
PlaceStep = function( only )
	local st, m = RPL.st, RPL.model
	if not st or not m or not st.canManage or not RPL.IsRaidKind( st.kind ) then return false end
	local target = m.target
	for _, e in ipairs( m.misplaced ) do
		if not only or only.name == e.name then
			local tg = target[ e.name ].g
			if G.CanMoveTo( st, e, tg ) then
				G.Move( st, e, tg )
				RPL.Log( "расстановка:", e.name, e.g, "->", tg ) --@debug
				return true
			end
			for _, o in ipairs( st.groups[ tg ] or {} ) do
				local ot = target[ o.name ]
				if not ot or ot.g ~= tg then
					G.Swap( st, e, o )
					RPL.Log( "расстановка: обмен", e.name, "<->", o.name ) --@debug
					return true
				end
			end
		end
	end
	-- все в своих группах — восстанавливаем порядок внутри групп
	if #m.misplaced == 0 or only then
		for _, e in ipairs( m.misordered ) do
			if ( not only or only.name == e.name ) and e.orderSwap then
				G.Swap( st, e, e.orderSwap )
				RPL.Log( "порядок: обмен", e.name, "<->", e.orderSwap.name ) --@debug
				return true
			end
		end
	end
	if only and only.misplaced then
		local t = target[ only.name ]
		local _, why = G.CanMoveTo( st, only, t and t.g or 1 )
		RPL.Toast( why or RPL.F( RPL.L.toastFull, t and t.g or 1 ) )
	end
	return false
end

--------------------------------------------------------------------------------
-- Выбор и действия на карточках
--------------------------------------------------------------------------------
local function SlotFromWidget( w )
	local slot = w and w:GetParent()
	local grp = slot and slot:GetParent()
	if not grp then return end
	local k = tonumber( string.match( slot:GetName() or "", "^Slot(%d)$" ) or "" )
	local g = tonumber( string.match( grp:GetName() or "", "^Group(%d)$" ) or "" )
	if not k or not g then return end
	local m = RPL.model
	local e = m and m.groups[ g ] and m.groups[ g ][ k ]
	return e, g, k
end

local function Deselect()
	RPL.sel = nil
end

--------------------------------------------------------------------------------
-- Выпадающее меню «Дележ» / «Ценность»
--------------------------------------------------------------------------------
local menu = nil -- { kind = "scheme" | "quality" | "link", mode = "current" | "detail", items }

local function CloseMenu()
	if not menu then return end
	menu = nil
	RPL.Show( RPL.W( "LootMenu" ), false )
end

-- Сохранённые формирования для ручной связи с текущим составом: сначала те,
-- где больше игроков из текущего состава (себя не считаем), затем новые.
-- Подпись: «Название · 8/10» — сколько участников сохранённого сейчас в составе.
local function LinkItems()
	local st = RPL.st
	local items = {}
	-- вне группы связывать не с чем: скрепка только отменяет сбор, если он идёт
	if not st or st.kind == "none" then
		if RPL.link then items[ 1 ] = { unlink = true, label = RPL.L.linkCancel } end
		return items
	end
	for order, f in ipairs( Store.List() ) do
		local here, total = 0, #( f.members or {} )
		for _, t in ipairs( f.members or {} ) do
			if st and st.byName[ t.n ] and t.n ~= st.me then here = here + 1 end
		end
		if st and st.byName[ st.me ] then here = here + 1 end -- аватар всегда в составе
		items[ #items + 1 ] = { id = f.id, here = here, order = order,
			label = RPL.F( RPL.L.linkItem, f.name, here, total ) .. ( f.id == RPL.link and RPL.L.linkCurrent or "" ) }
	end
	table.sort( items, function( a, b )
		if a.here ~= b.here then return a.here > b.here end
		return a.order < b.order
	end )
	local max = RPL.link and 7 or 8
	while #items > max do table.remove( items ) end
	if RPL.link then items[ #items + 1 ] = { unlink = true, label = RPL.L.linkUnlink } end
	return items
end

local function OpenMenu( kind )
	if menu and menu.kind == kind then CloseMenu() return end
	local items
	if kind == "link" then
		items = LinkItems()
		if #items == 0 then
			RPL.Toast( ( RPL.st and RPL.st.kind ~= "none" ) and RPL.L.linkNone or RPL.L.linkNoGroup )
			return
		end
	else
		items = ( kind == "scheme" ) and RPL.SCHEMES or RPL.QUALITIES
	end
	menu = { kind = kind, mode = ( RPL.tab == "detail" or RPL.tab == "quick" ) and "detail" or "current", items = items }
	local P = RPL.Px
	-- меню связи шире: в нём названия формирований
	local menuW = P( kind == "link" and 320 or 180 )
	for i = 1, 8 do
		local o = RPL.W( "MenuOpt" .. i )
		local op = o:GetPlacementPlain()
		op.sizeX = menuW - P( 12 )
		o:SetPlacementPlain( op )
		local t = RPL.W( "MenuText" .. i )
		local tp = t:GetPlacementPlain()
		tp.sizeX = menuW - P( 12 ) - P( kind == "quality" and 32 or 16 )
		t:SetPlacementPlain( tp )
	end
	for i = 1, 8 do
		local opt, it = RPL.W( "MenuOpt" .. i ), items[ i ]
		RPL.Show( opt, it ~= nil )
		if it then
			-- подпись — отдельное поле: у ценности отступ после цветной точки
			local text = RPL.W( "MenuText" .. i )
			RPL.SetText( text, it.label )
			local tp = text:GetPlacementPlain()
			tp.posX = RPL.Px( kind == "quality" and 28 or 12 )
			text:SetPlacementPlain( tp )
			local dot = RPL.W( "MenuDot" .. i )
			RPL.Show( dot, kind == "quality" and RPL.SetTex( dot, "Icons", "Q_" .. it.key ) )
		end
	end
	-- под нажатой кнопкой (координаты макета, с масштабом)
	local w = RPL.W( "LootMenu" )
	local p = w:GetPlacementPlain()
	if kind == "link" then
		-- под панелью связи, по её правому краю
		local winW = V.ui.window:GetPlacementPlain().sizeX
		p.posX = winW - P( 14 ) - menuW
		p.posY = P( 82 + 12 + 46 + 2 )
	else
		p.posX = P( 14 ) + ( kind == "scheme" and P( 48 ) or P( 290 ) )
		p.posY = P( 146 + 30 + 2 )
	end
	p.sizeX = menuW
	p.sizeY = P( 12 + #items * 26 )
	w:SetPlacementPlain( p )
	RPL.Show( w, true )
end

local function OnMenuPick( params )
	local i = tonumber( string.match( params.sender or "", "^MenuOpt(%d)$" ) or "" )
	local m = menu
	CloseMenu()
	if not m or not i then return end
	local it = m.items and m.items[ i ]
	if not it then return end
	if m.kind == "link" then
		if it.unlink then
			ResetLink()
			RPL.Toast( RPL.L.linkUnlinked )
		elseif it.id ~= RPL.link and RPL.st and RPL.st.kind ~= "none" then
			-- скрепка = «мы в этом сохранённом»: работают Shift+ПКМ, «Пригласить всех», расстановка
			ResetLink()
			RPL.link = it.id
			Store.SetLink( it.id )
			local f = Store.Get( it.id )
			RPL.Toast( RPL.F( RPL.L.linkDone, f and f.name or "" ) )
		end
	elseif m.mode == "detail" then
		local f = V.DetailF()
		if f then
			Store.SetLoot( f.id, m.kind == "scheme" and it.key or f.lootScheme, m.kind == "quality" and it.key or f.lootQuality )
			RPL.savedDirty = true
		end
	else
		local st = RPL.st
		if not st or not st.canLoot then RPL.Toast( RPL.L.toastNotLeader ) return end
		if RPL.asm then RPL.asm.lootManual = true end -- выбрали руками: автовыставление не вмешивается
		if m.kind == "scheme" then G.SetLootScheme( it.key ) else G.SetLootQuality( it.key ) end
		Acted()
	end
	RPL.Refresh()
end

local function MoveSelectedTo( g )
	local st = RPL.st
	local sel = RPL.sel and st and st.byName[ RPL.sel ]
	if not sel or sel.g == g then return end
	if not st.canManage then RPL.Toast( RPL.L.toastNotLeader ) return end
	local ok, why = G.CanMoveTo( st, sel, g )
	if not ok then
		if why then RPL.Toast( why ) end
		return
	end
	if G.Move( st, sel, g ) then Acted() Deselect() end
end

-- Поменять местами a и b — только между разными группами отряда
local function SwapEntries( a, b )
	if G.Swap( RPL.st, a, b ) then Acted() end
end

local function OnSlot( params )
	if RPL.tab ~= "current" then return end
	local e, g, k = SlotFromWidget( params.widget )
	RPL.Log( "слот", "группа=" .. tostring( g ), "место=" .. tostring( k ), "игрок=" .. tostring( e and e.name ), "выбран=" .. tostring( RPL.sel ) ) --@debug
	if not e then
		if RPL.sel then MoveSelectedTo( g ) end
	elseif e.pending then
		Deselect()
	elseif RPL.sel == e.name then
		Deselect()
	else
		RPL.sel = e.name -- клик по другому участнику только перевыбирает
	end
	RPL.Refresh()
end

local function OnSwap( params )
	local e = SlotFromWidget( params.widget )
	local st = RPL.st
	local sel = RPL.sel and st.byName[ RPL.sel ]
	if e and sel and e.live then SwapEntries( sel, e ) end
	Deselect()
	RPL.Refresh()
end

local function OnHome( params )
	local e = SlotFromWidget( params.widget )
	if e and ( e.misplaced or e.misordered ) and PlaceStep( e ) then Acted() end
	Deselect()
	RPL.Refresh()
end

local function OnRetry( params )
	local e = SlotFromWidget( params.widget )
	if e and e.pending then InviteOne( e.name ) end
	RPL.Refresh()
end

-- Помощник может приглашать и переставлять, но назначать роли и исключать — только лидер
local function RequireLeader()
	if RPL.st and RPL.st.isLeader then return true end
	RPL.Toast( RPL.L.toastOnlyLeader )
	return false
end

local function OnKick( params )
	local e = SlotFromWidget( params.widget )
	if e and e.live and RequireLeader() then G.Kick( RPL.st, e ) Acted() end
	Deselect()
	RPL.Refresh()
end

local function OnGroupHeader( params )
	local grp = params.widget and params.widget:GetParent()
	local g = grp and tonumber( string.match( grp:GetName() or "", "^Group(%d)$" ) or "" )
	if g and RPL.sel and RPL.tab == "current" then MoveSelectedTo( g ) end
	RPL.Refresh()
end

local function SelectedEntry()
	local st = RPL.st
	return RPL.sel and st and st.byName[ RPL.sel ]
end

local function OnAssist()
	local e = SelectedEntry()
	if e and RequireLeader() then
		if RPL.asm then RPL.asm.rolesManual = true end
		G.ToggleAssist( e )
		Acted()
	end
	Deselect()
	RPL.Refresh()
end

local function OnLoot()
	local e = SelectedEntry()
	if e and not RequireLeader() then e = nil end
	if e and RPL.asm then RPL.asm.rolesManual = true end
	if e and e.leader then
		-- лидер: снимаем текущего ответственного, тогда добычу распределяет лидер
		for _, o in ipairs( RPL.st.list ) do
			if o.loot and not o.leader then G.ToggleLoot( o ) end
		end
		RPL.Toast( RPL.L.toastLootLeader )
		Acted()
	elseif e then
		G.ToggleLoot( e )
		Acted()
	end
	Deselect()
	RPL.Refresh()
end

-- Передать лидерство выбранному. Это не отменить самому, поэтому нужно нажать дважды
-- за 3 секунды: первое нажатие только предупреждает.
local leaderConfirm = nil -- { name, t }

local function OnLeader()
	local e = SelectedEntry()
	local st = RPL.st
	if not e or not st or e.name == st.me or not e.live then return end
	if not RequireLeader() then return end
	if e.offline then RPL.Toast( RPL.F( RPL.L.toastLeaderOffline, e.name ) ) return end
	if not ( leaderConfirm and leaderConfirm.name == e.name and RPL.tick - leaderConfirm.t <= 3 ) then
		leaderConfirm = { name = e.name, t = RPL.tick }
		RPL.Toast( RPL.F( RPL.L.toastLeaderConfirm, e.name ), true ) -- подтверждение: показываем всегда
		return
	end
	leaderConfirm = nil
	G.SetLeader( st, e )
	Acted()
	Deselect()
	RPL.Refresh()
end

local function OnKickSelected()
	local e = SelectedEntry()
	if e and e.name ~= RPL.st.me and RequireLeader() then G.Kick( RPL.st, e ) Acted() end
	Deselect()
	RPL.Refresh()
end

local function OnInviteAll()
	if RPL.link then Assemble( RPL.link, false ) end
	RPL.Refresh()
end

local function OnPlaceAll()
	RPL.placing = 30 -- секунд на всю расстановку; шаги идут по одному
	Deselect()
	RPL.Refresh()
end

local function OnInvite()
	local edit = RPL.W( "InviteNameEdit" )
	local name = RPL.Trim( RPL.S( edit:GetText() ) )
	if not RPL.ValidNick( name ) then
		RPL.Toast( RPL.L.toastNick )
		return
	end
	G.Invite( name )
	edit:SetText( RPL.WS( "" ) )
	RPL.Toast( RPL.F( RPL.L.toastInvited, name ) )
end

--------------------------------------------------------------------------------
-- Проверка готовности
--------------------------------------------------------------------------------
local READY_SHOW_AFTER = 15 -- секунд показываем результат после окончания проверки

local function OnReady()
	local st = RPL.st
	if not st or not st.canReady then RPL.Toast( RPL.L.toastReadyRights ) return end
	if st.readyActive then RPL.Toast( RPL.L.toastReadyBusy ) return end
	G.StartReadyCheck( st.kind )
	RPL.readyMine = true
end

local function OnReadyStarted()
	RPL.readyShow, RPL.readyUntil = true, nil
	RPL.Refresh()
end

local function OnReadyEnded()
	RPL.readyShow, RPL.readyUntil = true, RPL.tick + READY_SHOW_AFTER
	RPL.Refresh()
	-- итог — тому, кто запускал проверку из аддона
	if not RPL.readyMine then return end
	RPL.readyMine = nil
	local st = RPL.st
	if not st then return end
	local notReady, wait, n = {}, {}, 0
	for _, e in ipairs( st.list ) do
		n = n + 1
		if e.ready == "notready" then notReady[ #notReady + 1 ] = e.name
		elseif e.ready ~= "ready" then wait[ #wait + 1 ] = e.name end
	end
	if #notReady == 0 and #wait == 0 then
		RPL.Toast( RPL.F( RPL.L.toastReadyAll, n ) )
	else
		local parts = {}
		if #notReady > 0 then parts[ #parts + 1 ] = RPL.F( RPL.L.toastReadyNot, table.concat( notReady, ", " ) ) end
		if #wait > 0 then parts[ #parts + 1 ] = RPL.F( RPL.L.toastReadyWait, table.concat( wait, ", " ) ) end
		RPL.Toast( table.concat( parts, ". " ) )
	end
end


--------------------------------------------------------------------------------
-- Окно, вкладки, сохранённые
--------------------------------------------------------------------------------
local function ShowWindow( on )
	if not on then CloseMenu() end
	RPL.Show( V.ui.window, on )
	RPL.Show( RPL.W( "RPLRing" ), on ) -- состояние кнопки «окно открыто»
	if on then RPL.Refresh() end
end

local dragEnd = nil -- тик окончания перетаскивания кнопки

-- Кнопку RPL сейчас тащат и она уже сдвинулась?
local function ButtonDragMoved()
	local id = DnD.Dragging
	local w = id and DnD.Widgets and DnD.Widgets[ id ]
	if not w or w.wtMovable:GetName() ~= "RPLHost" then return false end
	local p, r = DnD.Place, DnD.Reset
	return ( p and r and ( p.posX ~= r.posX or p.posY ~= r.posY ) ) and true or false
end

local function OnToggle()
	if ButtonDragMoved() then return end
	if dragEnd and RPL.tick - dragEnd <= 1 then
		dragEnd = nil
		return -- это было перетаскивание, а не клик
	end
	dragEnd = nil
	ShowWindow( not V.ui.window:IsVisible() )
end

local function OnClose()
	ShowWindow( false )
end

local function SetTab( tab )
	CloseMenu()
	RPL.tab = tab
	Deselect()
	if tab == "saved" then RPL.savedDirty = true end
	RPL.Refresh()
end

local function RowId( params )
	local row = params.widget and params.widget:GetParent()
	return row and tonumber( string.match( row:GetName() or "", "^Row(%d+)$" ) or "" )
end

local function OnOpen( params )
	local id = RowId( params )
	if not id then return end
	RPL.detailId = id
	SetTab( "detail" )
end

local function OnDelete( params )
	local id = RowId( params )
	local f = id and Store.Delete( id )
	if not f then return end
	if RPL.link == id then ResetLink() end
	RPL.savedDirty = true
	RPL.Toast( RPL.F( RPL.L.toastDeleted, f.name ) )
	RPL.Refresh()
end

local function RolesText( f )
	return "помощники=[" .. table.concat( f.assist or {}, ", " ) .. "] добыча=" .. tostring( f.loot )
end

-- «Пригласить всех» на карточке сохранённого и во вкладке «Быстрое»
local function OnStartInvite()
	local f, key = V.DetailF()
	local st = RPL.st
	if not f or not st or not V.CanAssemble( st, f, key ) then return end
	RPL.Log( "сбор:", f.name, RolesText( f ) ) --@debug
	Assemble( key, false )
	SetTab( "current" )
end

--------------------------------------------------------------------------------
-- Кнопка RPL: ПКМ — запомнить, Shift+ПКМ — собрать / привести в готовность
--------------------------------------------------------------------------------
-- ПКМ: мы в сохранённом — в «Быстрое» ложится ссылка на него (снимок не нужен, связь не
-- трогаем). Иначе — снимок текущего состава, и «Текущее» сразу связано с ним: это тот же
-- отряд. Вне группы — ничего.
local function OnSnapshot()
	local st = RPL.st
	if not st or st.kind == "none" or not RPL.model then return end
	local f = Store.Get( RPL.link )
	-- Ожидаем: идёт сбор снимка, пришли ещё не все — ПКМ заменил бы снимок неполным
	-- составом. Не заменяем и говорим, как запомнить новый состав.
	if RPL.link == Store.QUICK and Store.QuickIsSnap() and RPL.asm and RPL.asm.active then
		RPL.Toast( RPL.L.toastQuickBusy )
		return
	end
	if f and RPL.link ~= Store.QUICK then
		Store.SetQuickRef( RPL.link )
		RPL.Toast( RPL.F( RPL.L.toastQuickRef, f.name ) )
		return
	end
	local rec = V.BuildRecord( st, RPL.model )
	if #rec.members == 0 then return end
	local name = RPL.F( RPL.L.quickName, RPL.L.kindShort[ rec.kind ] or "", #rec.members, RPL.Stamp() )
	Store.SetQuickSnap( rec, name )
	RPL.order = {}
	RPL.asm = nil
	RPL.link = Store.QUICK
	Store.SetLink( Store.QUICK )
	RPL.Toast( RPL.F( RPL.L.toastQuickSnap, name ) )
end

-- Shift+ПКМ: вне группы — собрать «Быстрое»; в своём (связанном) формировании —
-- привести его в боевую готовность; в неизвестном составе или без прав — ничего.
local function OnQuickAssemble()
	local st = RPL.st
	if not st then return end
	if st.kind == "none" then
		local key = Store.QuickKey()
		if key then Assemble( key, true ) end
		return
	end
	if not st.canInvite or not RPL.link or not Store.Get( RPL.link ) then return end
	Assemble( RPL.link, true )
end

local function OnRmb( params )
	if RPL.Shift( params ) then OnQuickAssemble() else OnSnapshot() end
	RPL.Refresh()
end

-- «Быстрое»: снимок удаляем (если «Текущее» было связано с ним — оно становится
-- неизвестным), ссылку на сохранённое просто убираем
local function OnQuickDelete()
	if Store.QuickIsSnap() then
		Store.ClearQuick()
		if RPL.link == Store.QUICK then ResetLink() end
		RPL.Toast( RPL.L.toastQuickDeleted )
	elseif Store.QuickKey() then
		Store.ClearQuick()
		RPL.Toast( RPL.L.toastQuickRemoved )
	end
	RPL.Refresh()
end

--------------------------------------------------------------------------------
-- Диалог сохранения / переименования
--------------------------------------------------------------------------------
local function OpenDialog( mode, id )
	local st = RPL.st
	RPL.dialog = { mode = mode, id = id }
	local title, value, auto
	if mode == "rename" then
		local f = Store.Get( id )
		if not f then return end
		title = RPL.L.dlgRename
		value = f.name
		auto = Store.AutoName( f.kind, f.id )
	elseif mode == "quick" then
		local f = Store.Get( Store.QUICK )
		if not f then return end
		title = RPL.L.dlgSaveQuick
		value = ""
		auto = Store.AutoName( f.kind, Store.NextId() )
	else
		local raidKind = RPL.IsRaidKind( st.kind )
		title = raidKind and RPL.L.dlgSaveRaid or RPL.L.dlgSaveParty
		value = ""
		auto = Store.AutoName( st.kind, Store.NextId() )
	end
	RPL.SetText( RPL.W( "DialogTitle" ), title )
	RPL.SetText( RPL.W( "DialogHint" ), RPL.F( RPL.L.dlgHint, auto ) )
	local edit = RPL.W( "NameEdit" )
	edit:SetText( RPL.WS( value ) )
	RPL.Show( RPL.W( "SaveDialog" ), true )
	edit:SetFocus( true )
end

local function CloseDialog()
	RPL.dialog = nil
	RPL.Show( RPL.W( "SaveDialog" ), false )
end

local function OnDialogOk()
	local d = RPL.dialog
	if not d then return end
	local name = RPL.Trim( RPL.S( RPL.W( "NameEdit" ):GetText() ) )
	if RPL.CharLen( name ) > RPL.NAME_MAX then name = string.sub( name, 1, RPL.NAME_MAX ) end
	-- название уникально (без учёта регистра), пустое — автоназвание
	local final, except = name, nil
	if d.mode == "rename" then
		local f = Store.Get( d.id )
		except = d.id
		if final == "" and f then final = Store.AutoName( f.kind, f.id ) end
	elseif d.mode == "quick" then
		local f = Store.Get( Store.QUICK )
		if final == "" and f then final = Store.AutoName( f.kind, Store.NextId() ) end
	elseif final == "" and RPL.st then
		final = Store.AutoName( RPL.st.kind, Store.NextId() )
	end
	if Store.NameTaken( final, except ) then
		RPL.SetText( RPL.W( "DialogHint" ), RPL.L.nameTaken )
		return -- окно остаётся открытым
	end
	if d.mode == "rename" then
		Store.Rename( d.id, name )
		local f = Store.Get( d.id )
		RPL.Toast( RPL.F( RPL.L.toastRenamed, f and f.name or name ) )
	elseif d.mode == "quick" then
		-- снимок из «Быстрого» -> в «Сохранённые»; «Быстрое» и связь переходят на сохранённое
		local snap = Store.Get( Store.QUICK )
		if not snap then CloseDialog() return end
		local rec = RPL.Copy( snap )
		rec.id, rec.name = nil, nil
		local id = Store.Add( rec, name )
		Store.SetQuickRef( id )
		if RPL.link == Store.QUICK then
			RPL.link = id
			Store.SetLink( id )
		end
		RPL.Toast( RPL.F( RPL.L.toastSaved, Store.Get( id ).name ) )
	else
		local st = RPL.st
		if st.kind == "none" then CloseDialog() return end
		local rec, skipped = V.BuildRecord( st, RPL.model )
		local id = Store.Add( rec, name )
		RPL.Log( "сохранено:", Store.Get( id ).name, RolesText( Store.Get( id ) ) ) --@debug
		-- сохранили состав, снятый в «Быстрое», — «Быстрое» теперь ссылается на сохранённое
		if RPL.link == Store.QUICK and Store.QuickIsSnap() then Store.SetQuickRef( id ) end
		RPL.link = id
		Store.SetLink( id )
		RPL.order = {}
		local msg = RPL.F( RPL.L.toastSaved, Store.Get( id ).name )
		if skipped > 0 then msg = RPL.F( RPL.L.toastForeign, msg, skipped ) end
		RPL.Toast( msg )
	end
	RPL.savedDirty = true
	CloseDialog()
	RPL.Refresh()
end

local function OnUpdate()
	local f = Store.Get( RPL.link )
	if not f or RPL.link == Store.QUICK or RPL.st.kind == "none" then return end
	local rec, skipped = V.BuildRecord( RPL.st, RPL.model )
	Store.Update( f.id, rec )
	RPL.Log( "обновлено:", f.name, RolesText( f ) ) --@debug
	RPL.order = {}
	RPL.savedDirty = true
	local msg = RPL.F( RPL.L.toastUpdated, f.name )
	if skipped > 0 then msg = RPL.F( RPL.L.toastForeign, msg, skipped ) end
	RPL.Toast( msg )
	RPL.Refresh()
end

--------------------------------------------------------------------------------
-- Таймер
--------------------------------------------------------------------------------


--@debug
--------------------------------------------------------------------------------
-- Отладочная сборка: через 3 секунды после загрузки пишет в чат, что игра отдаёт
-- о сервере и фракции каждого участника (в обычной сборке этого блока нет).
--------------------------------------------------------------------------------
local function DS( v )
	if v == nil then return "nil" end
	local t = type( v )
	if t == "string" or t == "number" or t == "boolean" then return tostring( v ) end
	if apitype( v ) == "WString" then return RPL.S( v ) end
	return "<" .. tostring( apitype( v ) ) .. ">"
end

local function Keys( tbl )
	if type( tbl ) ~= "table" then return DS( tbl ) end
	local parts = {}
	for k, v in pairs( tbl ) do parts[ #parts + 1 ] = tostring( k ) .. "=" .. DS( v ) end
	table.sort( parts )
	return table.concat( parts, " " )
end

local function FactionText( fid )
	if fid == nil then return "nil" end
	local info = fid:GetInfo()
	local out = type( info ) == "table" and ( DS( info.sysName ) .. "/" .. DS( info.name ) ) or ""
	local fi = avatar.GetFactionInfo( fid )
	if type( fi ) == "table" then
		out = out .. ( fi.isSame and " СВОЯ" or " чужая" ) .. ( fi.isFriend and " друж" or "" )
	end
	return out
end

local function CrossDump()
	local D = function( ... ) RPL.Chat( "[RPL cross] " .. table.concat( { ... }, " " ), "notice" ) end
	local myId = avatar.GetId()
	D( "я:", DS( object.GetName( myId ) ), "сервер=" .. DS( unit.GetPlayerShardName( myId ) ),
		"миссия=" .. DS( mission.GetShardName() ), "фракция=" .. FactionText( unit.GetFactionId( myId ) ) )
	D( "общий сервер=" .. DS( cartographer.IsOnCommon() ), "в событии=" .. DS( matchMaking.IsAvatarInMatchMakingEvent() ) )
	local list = {}
	if raid.IsExist() then
		for _, grp in ipairs( raid.GetMembers() or {} ) do for _, m in ipairs( grp ) do list[ #list + 1 ] = m end end
	elseif group.IsExist() then
		for _, m in ipairs( group.GetMembers() or {} ) do list[ #list + 1 ] = m end
	end
	D( "участников:", #list )
	for i, m in ipairs( list ) do
		local shard, fac = "не видно", "не видно"
		if m.id and object.IsExist( m.id ) then
			shard = DS( unit.GetPlayerShardName( m.id ) )
			fac = FactionText( unit.GetFactionId( m.id ) )
		end
		D( i .. ".", DS( m.name ), "сервер=" .. shard, "фракция=" .. fac )
		if i == 1 then D( "поля участника:", Keys( m ) ) end
	end
end
local crossDumpAt = nil
--@end
local function OnSecond()
	RPL.tick = RPL.tick + 1
	--@debug
	if crossDumpAt and RPL.tick >= crossDumpAt then
		crossDumpAt = nil
		CrossDump()
	end
	--@end
	RPL.ToastTick()
	if RPL.readyUntil and RPL.tick >= RPL.readyUntil then
		RPL.readyShow, RPL.readyUntil = false, nil
	end
	if RPL.placing > 0 then
		RPL.placing = RPL.placing - 1
		local left = RPL.model and ( #RPL.model.misplaced + #RPL.model.misordered ) or 0
		if RPL.placing == 0 and left > 0 then
			RPL.Warn( "не всех удалось расставить:", left )
		end
	end
	RPL.Refresh()
end

--------------------------------------------------------------------------------
-- События игры
--------------------------------------------------------------------------------
--@debug
-- Отладка: какие события вообще приходят при приглашении (поля выводятся в чат)
local PROBE_EVENTS = {
	"EVENT_GROUP_DECLINE", "EVENT_GROUP_DECLINE_BUSY", "EVENT_GROUP_DECLINE_IGNORED", "EVENT_GROUP_INVITE_FAILED",
	"EVENT_GROUP_INVITE_END", "EVENT_GROUP_ACCEPT_ERROR",
	"EVENT_RAID_DECLINE", "EVENT_RAID_DECLINE_BUSY", "EVENT_RAID_DECLINE_IGNORED", "EVENT_RAID_ALREADY_IN",
	"EVENT_RAID_FAILED", "EVENT_RAID_INVITE_END", "EVENT_GENERAL_ERROR", "EVENT_ADDRESSEE_NOT_FOUND",
}

local function ProbeEvent( name )
	return function( p )
		if not RPL.DEBUG then return end
		local parts = {}
		for k, v in pairs( p or {} ) do parts[ #parts + 1 ] = tostring( k ) .. "=" .. RPL.S( v ) end
		RPL.Log( "событие", name, table.concat( parts, " " ) ) --@debug
	end
end
--@end

-- События отряда приходят пачками (MEMBER_CHANGED — на любое изменение участника),
-- поэтому по событиям обновляемся не чаще раза в 0,3 с; остальное догонит секундный таймер.
local lastEventRefresh = 0

local function OnChanged()
	pace.waiting = false -- сервер ответил: можно следующую операцию
	local now = common.GetAbsTimeMs()
	if now - lastEventRefresh < 300 then return end
	lastEventRefresh = now
	RPL.Refresh()
end

local CHANGE_EVENTS = {
	"EVENT_GROUP_APPEARED", "EVENT_GROUP_DISAPPEARED", "EVENT_GROUP_CHANGED", "EVENT_GROUP_CONVERTED",
	"EVENT_GROUP_MEMBER_ADDED", "EVENT_GROUP_MEMBER_REMOVED", "EVENT_GROUP_LEADER_CHANGED", "EVENT_GROUP_MEMBER_CHANGED",
	"EVENT_RAID_APPEARED", "EVENT_RAID_DISAPPEARED", "EVENT_RAID_CHANGED",
	"EVENT_RAID_MEMBER_ADDED", "EVENT_RAID_MEMBER_REMOVED", "EVENT_RAID_LEADER_CHANGED", "EVENT_RAID_MEMBER_CHANGED",
	"EVENT_RAID_LEADER_HELPER_CHANGED", "EVENT_RAID_LOOT_MASTER_CHANGED",
	"EVENT_GROUP_LOOT_SCHEME_CHANGED", "EVENT_GROUP_ITEM_QUALITY_CHANGED",
	"EVENT_READY_CHECK_INFO_CHANGED",
}

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------
-- Колокольчик в шапке: показывать ли уведомления
local function RenderBell()
	RPL.SetTex( RPL.W( "BellIcon" ), "Icons", RPL.toasts and "BELL_ON" or "BELL_OFF" )
end

local function OnBell()
	Store.SetToasts( not RPL.toasts )
	RenderBell()
	RPL.Toast( RPL.toasts and RPL.L.toastsOn or RPL.L.toastsOff, true )
end

local REACTIONS = {
	rpl_bell = OnBell,
	rpl_toggle = OnToggle,
	rpl_close = OnClose,
	rpl_tab_current = function() SetTab( "current" ) end,
	rpl_tab_saved = function() SetTab( "saved" ) end,
	rpl_tab_quick = function() SetTab( "quick" ) end,
	rpl_rmb = OnRmb,
	rpl_quick_save = function() if Store.QuickIsSnap() then OpenDialog( "quick" ) end end,
	rpl_quick_delete = OnQuickDelete,
	rpl_slot = OnSlot,
	rpl_swap = OnSwap,
	rpl_home = OnHome,
	rpl_retry = OnRetry,
	rpl_kick = OnKick,
	rpl_group = OnGroupHeader,
	rpl_assist = OnAssist,
	rpl_loot = OnLoot,
	rpl_kick_sel = OnKickSelected,
	rpl_leader = OnLeader,
	rpl_invite_all = OnInviteAll,
	rpl_place_all = OnPlaceAll,
	rpl_invite = OnInvite,
	InviteNameEdit_enter = OnInvite,
	InviteNameEdit_esc = function() RPL.W( "InviteNameEdit" ):SetFocus( false ) end,
	rpl_ready = OnReady,
	rpl_save = function() if RPL.st and RPL.st.kind ~= "none" then OpenDialog( "new" ) end end,
	rpl_save_copy = function() if RPL.st and RPL.st.kind ~= "none" then OpenDialog( "copy" ) end end,
	rpl_update = OnUpdate,
	rpl_rename = function( params ) local id = RowId( params ) if id then OpenDialog( "rename", id ) end end,
	rpl_open = OnOpen,
	rpl_delete = OnDelete,
	rpl_start_invite = OnStartInvite,
	rpl_dialog_ok = OnDialogOk,
	rpl_loot_scheme = function() OpenMenu( "scheme" ) end,
	rpl_loot_quality = function() OpenMenu( "quality" ) end,
	rpl_menu_pick = OnMenuPick,
	rpl_link_pick = function() OpenMenu( "link" ) end,
	rpl_dialog_cancel = CloseDialog,
	NameEdit_enter = OnDialogOk,
	NameEdit_esc = CloseDialog,
}

-- Кнопка может прислать реакцию дважды: при нажатии (active = true) и при
-- отпускании (active = false). Обрабатываем клик один раз.
local pressed = {}

local MENU_REACTIONS = { rpl_menu_pick = true, rpl_loot_scheme = true, rpl_loot_quality = true, rpl_link_pick = true }

local function Reaction( name, fn )
	return function( params )
		if not MENU_REACTIONS[ name ] then CloseMenu() end
		local w = params.widget
		local key = name .. ":" .. tostring( w and w:GetInstanceId() or params.sender )
		RPL.Log( "клик", name, "sender=" .. tostring( params and params.sender ), "active=" .. tostring( params and params.active ) ) --@debug
		if params and params.active == true then
			pressed[ key ] = true
		elseif params and params.active == false and pressed[ key ] then
			pressed[ key ] = nil
			return
		end
		fn( params )
	end
end

local function HookDnD()
	-- клик по кнопке RPL сразу после перетаскивания не открывает окно
	local stop = DnD.StopDragging
	DnD.StopDragging = function( ... )
		if ButtonDragMoved() then dragEnd = RPL.tick end
		return stop( ... )
	end
end

local function Start()
	if started then return end
	started = true
	Store.LoadSettings() --@debug
	Store.Load()
	Store.LoadGlobal()
	-- связь из конфига переживает перезаход: вне игры сменить отряд нельзя.
	-- Если после входа 2 секунды подряд вне группы — сбросится, как при выходе из формирования.
	RPL.link = Store.GetLink()
	if not Store.Get( RPL.link ) then RPL.link = nil end
	wasInGroup = RPL.link ~= nil
	V.Init()
	RPL.Show( V.ui.window, false )
	RPL.Show( RPL.W( "SaveDialog" ), false )
	RPL.Show( RPL.W( "Toast" ), false )
	RPL.Show( RPL.W( "SavedRow" ), false )
	RenderBell()

	RPL.MoveWindowPlaces()
	DnD.Init( RPL.W( "RPLHost" ), RPL.W( "RPLButton" ), true, true )
	DnD.Init( V.ui.window, RPL.W( "Header" ), true, true )
	DnD.Init( RPL.W( "Toast" ), nil, true, true )
	HookDnD()

	for name, fn in pairs( REACTIONS ) do common.RegisterReactionHandler( Reaction( name, fn ), name ) end
	local function On( fn, ev ) common.RegisterEventHandler( fn, ev ) end
	On( OnSecond, "EVENT_SECOND_TIMER" )
	for _, ev in ipairs( CHANGE_EVENTS ) do On( OnChanged, ev ) end
	On( OnReadyStarted, "EVENT_READY_CHECK_STARTED" )
	On( OnReadyEnded, "EVENT_READY_CHECK_ENDED" )
	On( G.OnEventProgress, "EVENT_MATCH_MAKING_EVENT_PROGRESS_ADDED" )
	--@debug
	if RPL.DEBUG then
		for _, ev in ipairs( PROBE_EVENTS ) do On( ProbeEvent( ev ), ev ) end
	end
	--@end

	RPL.Refresh()
	RPL.Log( "loaded", RPL.VERSION ) --@debug
	if RPL.DEBUG then crossDumpAt = RPL.tick + 3 end --@debug
end

common.RegisterEventHandler( Start, "EVENT_AVATAR_CREATED" )
if avatar.IsExist() then Start() end
