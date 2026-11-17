CURRENT = panel('CurrentView', (0, 82, None, 452, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), pick=True, children=[
  panel('LinkBar', (14, 12, None, 46, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), back=lay('panel'), children=[
    iconp('LinkIcon', (12, 15, 16, 16), 'IconLink'),
    value('LinkTitle', (36, 6, None, 18, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 275}), size=13),
    value('LinkState', (36, 24, None, 16, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 275}), size=12, color=DIM),
    button('LinkPickButton', (None, 8, 32, 30, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 155}), '', 'rpl_link_pick', style='secondary', visible=False, children=[iconp('LinkPickIcon', (8, 7, 16, 16), 'IconLink')]),
    button('UpdateButton', (None, 8, 90, 30, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 175}), 'Обновить', 'rpl_update', style='accent', visible=False),
    button('SaveAsNewButton', (None, 8, 160, 30, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 7}), 'Сохранить как новый', 'rpl_save_copy', style='secondary', visible=False),
    button('SaveButton', (None, 8, 140, 30, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 7}), 'Сохранить отряд', 'rpl_save', style='accent'),
  ]),
  value('InfoText', (14, 68, 400, 20), font=FONT_TITLE, size=14),
  panel('ActionsBar', (14, 354, None, 32, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), pick=True, children=[
    button('InviteAllButton', (0, 0, 164, 32), 'Пригласить всех · 0', 'rpl_invite_all', style='accent'),
    button('PlaceAllButton', (172, 0, 136, 32), '     Расставить · 0', 'rpl_place_all', style='pink', children=[iconp('PlaceAllIcon', (14, 10, 12, 12), 'IconFlag')], visible=False),
    button('LeaderButton', (None, 0, 32, 32, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 120}), '', 'rpl_leader', style='secondary', visible=False, children=[iconp('LeaderIcon', (8, 8, 16, 16), 'IconCrown')]),
    button('ReadyButton', (None, 0, 32, 32, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 160}), '', 'rpl_ready', style='secondary', visible=False, children=[iconp('ReadyIcon', (8, 8, 16, 16), 'IconReady')]),
    button('AssistButton', (None, 0, 32, 32, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 80}), '', 'rpl_assist', style='secondary', children=[iconp('AssistIcon', (8, 8, 16, 16), 'IconStar')]),
    button('LootButton', (None, 0, 32, 32, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 40}), '', 'rpl_loot', style='secondary', children=[iconp('LootIcon', (8, 8, 16, 16), 'IconBag')]),
    button('KickSelButton', (None, 0, 32, 32, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 0}), '', 'rpl_kick_sel', style='danger', children=[iconp('KickSelIcon', (8, 8, 16, 16), 'IconKick')]),
  ]),
  panel('Footer', (14, 396, None, 44, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), pick=True, children=[
    panel('FooterLine', (0, 0, None, 1, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), back=lay('line'), transparent=True),
    editline('InviteNameEdit', (0, 13, 150, 30), lay('field'), max_len=14),
    button('InviteButton', (158, 13, 110, 30), 'Пригласить', 'rpl_invite', style='secondary'),
  ]),
])
EMPTY = panel('EmptyView', (0, 82, None, 452, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), visible=False, pick=True, children=[
  text('EmptyTitle', (18, 26, 440, 20), 'Вы не в группе и не в отряде', font=FONT_TITLE, size=14),
  text('EmptyText', (18, 52, 440, 40), wrap=True, inner= 'Собрать: «Сохранённые» → формирование → «Пригласить всех». Или Shift+ПКМ по кнопке RPL — собрать то, что лежит в «Быстром».', size=12, color=MUTED, aligny='top'),
  button('OpenSavedButton', (18, 100, 190, 32), 'Открыть сохранённые', 'rpl_tab_saved', style='secondary'),
])
def chips(prefix, p):
    out = []
    for k, label, col in [('Party', 'Группа', '0xff9ccbff'), ('Raid', 'Отряд', '0xffffa45c'), ('Small', 'Отряд', '0xfff5d25a')]:
        out.append(panel(f'{prefix}{k}', p, back=lay('chip'+k), transparent=True, visible=(k == 'Raid'),
                         children=[text(f'{prefix}{k}Text', (0, 0, p[2], p[3]), label.upper(), size=11, color=col, alignx='center', shadow=False)]))
    return out
SAVED_ROW = panel('SavedRow', (0, 0, 442, 48), back=lay('panel'), visible=False, children=chips('RowKind', (10, 13, 64, 22)) + [
  value('RowName', (84, 6, 180, 18), size=13),
  value('RowMeta', (84, 26, 180, 16), size=11, color=DIM),
  button('RenameButton', (270, 9, 30, 30), '', 'rpl_rename', style='ghost', children=[iconp('RenameIcon', (8, 8, 14, 14), 'IconRename')]),
  button('OpenButton', (308, 9, 90, 30), 'Открыть', 'rpl_open', style='secondary'),
  button('DeleteButton', (406, 9, 30, 30), '', 'rpl_delete', style='ghost', children=[iconp('DeleteIcon', (7, 7, 16, 16), 'IconDelete')]),
])
SAVED_LIST = put('SavedList', 'WidgetScrollableContainer', placement((14, 10, 442, 432)) + '\t<widgetsArrangement>WIDGETS_ARRANGEMENT_T2B</widgetsArrangement>\n\t<elementsInterval>6</elementsInterval>\n')
SAVED = panel('SavedView', (0, 82, None, 452, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), visible=False, pick=True, children=[SAVED_LIST, SAVED_ROW,
  text('NoSavedText', (18, 26, 440, 40), wrap=True, inner= 'Пока ничего не сохранено. Соберите группу или отряд и нажмите «Сохранить».', size=12, color=MUTED, aligny='top', visible=False)])
DETAIL = panel('DetailView', (0, 82, None, 452, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), visible=False, pick=True, children=[
  button('BackButton', (14, 21, 28, 28), '', 'rpl_tab_saved', style='secondary', children=[iconp('BackIcon', (7, 7, 14, 14), 'IconBack')]),
  value('DetailTitle', (52, 12, None, 24, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 90}), font=FONT_TITLE, size=15),
  value('DetailMeta', (52, 36, None, 16, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 90}), size=12, color=DIM),
] + chips('DetailKind', (None, 24, 64, 22, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 14})) + [
  button('QuickSaveButton', (None, 20, 100, 30, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 122}), 'Сохранить', 'rpl_quick_save', style='accent', visible=False),
  button('QuickDeleteButton', (None, 21, 28, 28, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 86}), '', 'rpl_quick_delete', style='ghost', visible=False, children=[iconp('QuickDeleteIcon', (6, 6, 16, 16), 'IconDelete')]),
  button('StartInviteButton', (14, 354, 200, 32), 'Пригласить всех · 0', 'rpl_start_invite', style='accent'),
  value('InviteNote', (224, 354, None, 32, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), wrap=True, size=12, color=MUTED),
])
QUICK_EMPTY = panel('QuickEmptyView', (0, 82, None, 452, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), visible=False, pick=True, children=[
  text('QuickEmptyTitle', (18, 26, 440, 20), 'В «Быстром» пока пусто', font=FONT_TITLE, size=14),
  text('QuickEmptyText', (18, 52, 440, 60), wrap=True, inner= 'ПКМ по кнопке RPL запомнит текущий состав для быстрого сбора. Если вы в сохранённом формировании — сюда ляжет оно само. Shift+ПКМ по RPL собирает то, что здесь лежит.', size=12, color=MUTED, aligny='top'),
])
# строка дележа: общая для «Текущего» и карточки сохранённого (лежит прямо в окне)
LOOTBAR = panel('LootBar', (14, 146, None, 30, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), pick=True, visible=False, children=[
  text('LootSchemeLabel', (0, 0, 48, 30), 'Дележ', size=12, color=MUTED),
  button('LootSchemeButton', (48, 0, 160, 30), 'Кому повезёт', 'rpl_loot_scheme', style='secondary', size=12),
  text('LootQualityLabel', (220, 0, 70, 30), 'Ценность', size=12, color=MUTED),
  button('LootQualityButton', (290, 0, 150, 30), '   Редкие', 'rpl_loot_quality', style='secondary', size=12,
         children=[panel('LootQualityDot', (12, 10, 10, 10), back=ic('QualityRare'), transparent=True)]),
])
# выпадающее меню селектора: до 8 пунктов, позиция и высота — из Lua
MENU = panel('LootMenu', (14, 178, 180, 220), back=lay('dialog'), visible=False, pick=True, prio=50, children=[
  button(f'MenuOpt{i}', (6, 6 + (i - 1) * 26, 168, 26), '', 'rpl_menu_pick', style='ghost', alignx='left', size=12,
         children=[panel(f'MenuDot{i}', (10, 8, 10, 10), back=ic('QualityRare'), transparent=True),
                   value(f'MenuText{i}', (28, 0, 136, 26), size=12, color='0xffe9e4ec')]) for i in range(1, 9)
])
WINDOW = panel('RPLWindow', (300, 60, 876, 534), back=lay('window'), visible=False, children=[HEADER, HEADER_LINE, TABS, CURRENT, EMPTY, SAVED, DETAIL, QUICK_EMPTY, GROUPS, LOOTBAR, MENU])
DIALOG = panel('SaveDialog', (0, 0, None, None, {'ax': 'WIDGET_ALIGN_BOTH', 'ay': 'WIDGET_ALIGN_BOTH'}), back=lay('dim'), visible=False, prio=900, children=[
  panel('DialogPanel', (0, 0, 380, 190, {'ax': 'WIDGET_ALIGN_CENTER', 'ay': 'WIDGET_ALIGN_CENTER'}), back=lay('dialog'), children=[
    value('DialogTitle', (18, 14, 344, 22), font=FONT_TITLE, size=15),
    text('NameLabel', (18, 44, 344, 16), 'Название', size=12, color='0xffc9c1cf'),
    editline('NameEdit', (18, 62, 344, 34), lay('field'), max_len=40),
    value('DialogHint', (18, 100, 344, 32), wrap=True, size=11, color=MUTED, aligny='top'),
    button('CancelButton', (154, 142, 100, 32), 'Отмена', 'rpl_dialog_cancel', style='secondary'),
    button('ConfirmButton', (262, 142, 100, 32), 'Сохранить', 'rpl_dialog_ok', style='accent'),
  ])])
TOAST = panel('Toast', (0, None, 420, 36, {'ax': 'WIDGET_ALIGN_CENTER', 'ay': 'WIDGET_ALIGN_HIGH', 'hy': 160}), back=lay('toast'), visible=False, prio=950,
              children=[value('ToastText', (0, 0, 420, 36), size=12, alignx='center')])
# кнопка RPL на 20% меньше остального интерфейса
BK = 0.8
RPLBTN = button('RPLButton', (4*BK, 6*BK, 64*BK, 32*BK), 'RPL', 'rpl_toggle', style='rpl', font=FONT_TITLE, size=14*BK, reaction_right='rpl_rmb')
# кольцо «окно открыто» и индикатор — соседи кнопки, а не дети: кнопка обрезает всё, что выходит за её края
RPLBUTTON = panel('RPLHost', (300, 8, 76*BK, 44*BK), pick=True, prio=800, children=[
  panel('RPLRing', (0, 2*BK, 72*BK, 40*BK), back=lay('rplRing'), transparent=True, visible=False),
  RPLBTN,
  # индикатор внутри кнопки, у правого края (сосед кнопки, лежит поверх неё)
  iconp('RPLBadge', ((4 + 49)*BK, (6 + 11)*BK, 10*BK, 10*BK), 'DotWarn', visible=False)])
# жирная подпись: у AllodsFantasy нет жирного начертания (обводка делала текст нечитаемым),
# поэтому единственный жирный шрифт игры — ContentNarrowBold
wtext('Texts/RPLButton.Format.txt', html('<r name="button_label"/>', font='ContentNarrowBold', size=15*BK, color='0xffffffff', alignx='center'))

wxml('Widgets/MainForm.(WidgetForm).xdb', f'''<?xml version="1.0" encoding="UTF-8" ?>
<WidgetForm>
\t<Name>MainForm</Name>
\t<Priority>1000</Priority>
\t<Children>
\t\t<Item href="{WINDOW}" />
\t\t<Item href="{RPLBUTTON}" />
\t\t<Item href="{DIALOG}" />
\t\t<Item href="{TOAST}" />
\t</Children>
\t<Placement>
\t\t<X>
\t\t\t<Align>WIDGET_ALIGN_BOTH</Align>
\t\t</X>
\t\t<Y>
\t\t\t<Align>WIDGET_ALIGN_BOTH</Align>
\t\t</Y>
\t</Placement>
\t<PickChildrenOnly>true</PickChildrenOnly>
\t<Visible>true</Visible>
</WidgetForm>
''')
wtext('Texts/AddonName.txt', 'RaidPartyLeader v0.11.1')
wtext('Texts/AddonDescription.txt', 'Сохраняет и собирает группы и отряды')
wxml('AddonDesc.(UIAddon).xdb', f'''<?xml version="1.0" encoding="UTF-8" ?>
<UIAddon>
\t<Name>RaidPartyLeader</Name>
\t<AutoStart>true</AutoStart>
\t<userAddonInfo>
\t\t<name href="Texts/AddonName.txt" />
\t\t<description href="Texts/AddonDescription.txt" />
\t\t<author>NoMercy</author>
\t\t<version>0.11.1</version>
\t</userAddonInfo>
\t<ScriptFileRefs>
\t\t<Item href="Scripts/LibDnD.lua" />
\t\t<Item href="Scripts/Util.lua" />
\t\t<Item href="Scripts/Storage.lua" />
\t\t<Item href="Scripts/Game.lua" />
\t\t<Item href="Scripts/View.lua" />
\t\t<Item href="Scripts/Main.lua" />
\t</ScriptFileRefs>
\t<Form href="Widgets/MainForm.(WidgetForm).xdb" />
\t<texturesGroups>
\t\t<Item>
\t\t\t<groupName>Classes</groupName>
\t\t\t<textures href="{G_CLASSES}" />
\t\t</Item>
\t\t<Item>
\t\t\t<groupName>Aspects</groupName>
\t\t\t<textures href="{G_ASPECTS}" />
\t\t</Item>
\t\t<Item>
\t\t\t<groupName>Icons</groupName>
\t\t\t<textures href="{G_ICONS}" />
\t\t</Item>
\t</texturesGroups>
</UIAddon>
''')
print('widgets', len(FILES), 'textures', len(T.made))
