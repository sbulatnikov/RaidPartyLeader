FONT_TITLE = 'AllodsFantasy'; FONT = 'AllodsSystem'
MUTED = '0xffa79dae'; DIM = '0xff958c9c'
# Масштаб всего интерфейса: координаты, размеры и шрифты (иконки и рамки рисуются в своих текстурах).
# В Lua тот же коэффициент — RPL.UI_SCALE (ширина окна, отступы).
import os as _os
SCALE = float(_os.environ.get('RPL_SCALE', '1.2'))
def sc(v):
    if v is None: return None
    r = int(v * SCALE + 0.5) if v >= 0 else -int(-v * SCALE + 0.5)
    return max(1, r) if v > 0 else r
def html(inner, font=FONT, size=13, color='0xffe9e4ec', alignx='left', aligny='middle', shadow=True):
    return f'<html fontname="{font}" fontsize="{sc(size)}" color="{color}" alignx="{alignx}" aligny="{aligny}"' + (' shadow="1"' if shadow else '') + f'>{inner}</html>'

def axis(tag, pos, size, align=None, high=None):
    pos, size, high = sc(pos), sc(size), sc(high)
    s = f'\t\t<{tag}>\n'
    if pos is not None: s += f'\t\t\t<Pos>{pos}</Pos>\n'
    if size is not None: s += f'\t\t\t<Size>{size}</Size>\n'
    if align: s += f'\t\t\t<Align>{align}</Align>\n'
    if high is not None: s += f'\t\t\t<HighPos>{high}</HighPos>\n'
    return s + f'\t\t</{tag}>\n'
def placement(p):
    x, y, w, h = p[:4]; o = p[4] if len(p) > 4 else {}
    return '\t<Placement>\n' + axis('X', x, w, o.get('ax'), o.get('hx')) + axis('Y', y, h, o.get('ay'), o.get('hy')) + '\t</Placement>\n'
FILES = {}
def put(name, wtype, body):
    fn = f'{name}.({wtype}).xdb'
    assert fn not in FILES, fn
    FILES[fn] = True
    wxml(f'Widgets/{fn}', f'<?xml version="1.0" encoding="UTF-8" ?>\n<{wtype}>\n\t<Name>{name}</Name>\n{body}</{wtype}>\n')
    return fn
def kids(children):
    if not children: return ''
    return '\t<Children>\n' + ''.join(f'\t\t<Item href="{c}" />\n' for c in children) + '\t</Children>\n'
def tail(visible=None, transparent=None, prio=None):
    s = ''
    if prio is not None: s += f'\t<Priority>{prio}</Priority>\n'
    if transparent: s += '\t<TransparentInput>true</TransparentInput>\n'
    if visible is not None: s += f'\t<Visible>{"true" if visible else "false"}</Visible>\n'
    return s
def panel(name, p, back=None, children=(), visible=None, transparent=None, prio=None, pick=None):
    # pick=True: the container itself ignores the mouse, its children still get clicks
    # (TransparentInput makes the whole subtree transparent)
    return put(name, 'WidgetPanel', placement(p) + (f'\t<BackLayer href="{back}" />\n' if back else '') + kids(children) + tail(visible, transparent, prio) + ('\t<PickChildrenOnly>true</PickChildrenOnly>\n' if pick else ''))
def text(name, p, inner, visible=None, wrap=False, **fmt):
    wtext(f'Texts/{name}.txt', html(inner, **fmt))
    style = '\t<TextStyle>\n\t\t<multiline>true</multiline>\n\t\t<wrapText>true</wrapText>\n\t</TextStyle>\n' if wrap else ''
    return put(name, 'WidgetTextView', placement(p) + '\t<TransparentInput>true</TransparentInput>\n' + f'\t<FormatFileRef href="../Texts/{name}.txt" />\n' + style + tail(visible))
def value(name, p, visible=None, wrap=False, **fmt):
    return text(name, p, '<r name="value"/>', visible, wrap, **fmt)
STYLES = {
 'accent': ('btnAccent', 'btnAccentHover', 'btnAccentPressed', 'btnAccentDisabled', '0xffffffff'),
 'secondary': ('btnSecondary', 'btnSecondaryHover', 'btnSecondaryPressed', 'btnSecondaryDisabled', '0xffe9e4ec'),
 'danger': ('btnDanger', 'btnDangerHover', 'btnDangerPressed', 'btnDangerDisabled', '0xffffb3c0'),
 'pink': ('btnPink', 'btnPinkHover', 'btnPinkPressed', 'btnPinkDisabled', '0xffffd3ec'),
 'ghost': ('ghost', 'ghostHover', 'ghostHover', 'ghost', '0xffdcd4e2'),
 'rpl': ('rpl', 'rplHover', 'rplPressed', 'rplDisabled', '0xffffffff'),
 'plain': ('ghost', None, 'ghost', 'ghost', '0xffdcd4e2'),
}
def button(name, p, label, reaction, style='secondary', children=(), visible=None, font=FONT, size=13, alignx='center', variants=None, prio=None, reaction_right=None):
    n, hv, pr, ds, col = STYLES[style]
    wtext(f'Texts/{name}.txt', label)
    wtext(f'Texts/{name}.Format.txt', html('<r name="button_label"/>', font=font, size=size, color=col, alignx=alignx))
    wtext(f'Texts/{name}.Disabled.txt', html('<r name="button_label"/>', font=font, size=size, color='0xff7f7686', alignx=alignx))
    def item(nl, hl, pl, dl):
        return (f'\t\t<Item>\n\t\t\t<TextFileRef href="../Texts/{name}.txt" />\n'
                + (f'\t\t\t<LayerHighlight href="{lay(hl)}" />\n' if hl else '')
                + '\t\t\t<PushedOffset x="0" y="1" />\n'
                + f'\t\t\t<StateNormal>\n\t\t\t\t<LayerMain href="{lay(nl)}" />\n\t\t\t\t<FormatFileRef href="../Texts/{name}.Format.txt" />\n\t\t\t</StateNormal>\n'
                + f'\t\t\t<StatePushed>\n\t\t\t\t<LayerMain href="{lay(pl)}" />\n\t\t\t</StatePushed>\n'
                + f'\t\t\t<StateDisabled>\n\t\t\t\t<LayerMain href="{lay(dl)}" />\n\t\t\t\t<FormatFileRef href="../Texts/{name}.Disabled.txt" />\n\t\t\t</StateDisabled>\n'
                + f'\t\t\t<Reaction>{reaction}</Reaction>\n'
                + (f'\t\t\t<ReactionRightClick>{reaction_right}</ReactionRightClick>\n' if reaction_right else '')
                + '\t\t\t<ReactionOnUp>true</ReactionOnUp>\n\t\t</Item>\n')
    vs = variants or [(n, hv, pr, ds)]  # hv may be None: no hover highlight
    body = (placement(p) + (f'\t<Priority>{prio}</Priority>\n' if prio is not None else '') + '\t<IgnoreDblClick>true</IgnoreDblClick>\n\t<TextTag>button_label</TextTag>\n\t<Variants>\n'
            + ''.join(item(*v) for v in vs) + '\t</Variants>\n\t<TextStyle>\n\t\t<Align>ALIGNY_MIDDLE</Align>\n\t</TextStyle>\n' + kids(children) + tail(visible))
    return put(name, 'WidgetButton', body)
def iconp(name, p, tex_name, visible=None):
    return panel(name, p, back=ic(tex_name), transparent=True, visible=visible)
def editline(name, p, back, max_len=None):
    # EditLine itself has no background: like working addons, a panel behind it draws the field
    w, h = p[2], p[3]
    wtext(f'Texts/{name}.txt', html('', size=13, color='0xffece6ef'))
    body = (placement((8, 0, w - 16, h)) + f'\t<Cursor1Layer href="{lay("cursor")}" />\n' + f'\t<Cursor2Layer href="{lay("cursor")}" />\n'
            + '\t<CursorWidth>1</CursorWidth>\n\t<CursorChangeTimeMs>500</CursorChangeTimeMs>\n'
            + f'\t<ReactionEnter>{name}_enter</ReactionEnter>\n\t<ReactionEsc>{name}_esc</ReactionEsc>\n'
            + '\t<TextStyle>\n\t\t<multiline>false</multiline>\n\t\t<wrapText>false</wrapText>\n\t\t<ellipsis>true</ellipsis>\n\t\t<Align>ALIGNY_MIDDLE</Align>\n\t</TextStyle>\n'
            + '\t<isPassword>false</isPassword>\n' + (f'\t<maxSymbolsCount>{max_len}</maxSymbolsCount>\n' if max_len else '')
            + f'\t<FormatFileRef href="../Texts/{name}.txt" />\n' + f'\t<selectionLayer href="{lay("selection")}" />\n')
    edit = put(name, 'WidgetEditLine', body)
    return panel(name + 'Box', p, back=back, children=[edit])

# slot (one set of files, shared by every slot of every group)
slot_children = [
  button('SlotButton', (0, 0, None, 30, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), '', 'rpl_slot', style='ghost', variants=[
      ('slot', 'slotHover', 'slotHover', 'slot'), ('slotSel', None, 'slotSel', 'slotSel'), ('slotMis', 'slotHover', 'slotMis', 'slotMis'),
      ('slotEmpty', 'slotHover', 'slotEmpty', 'slotEmpty'), ('slotTarget', 'slotHover', 'slotTarget', 'slotTarget')]),
  panel('ClassIcon', (2, 2, 26, 26), back=ic('ClassWarrior'), transparent=True),
  iconp('LeaderBadge', (19, -3, 14, 14), 'BadgeLeader'),
  iconp('AssistBadge', (19, -3, 14, 14), 'BadgeAssist', visible=False),
  iconp('LootBadge', (19, 15, 14, 14), 'BadgeLoot', visible=False),
  iconp('FactionBadge', (-3, 15, 14, 14), 'BadgeLeague', visible=False),
  panel('AspectIcon', (34, 6, 18, 18), back=ic('AspectDamage'), transparent=True),
  value('NameText', (58, 0, None, 30, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 32}), size=12, color='0xffece6ef'),
  panel('StatusIcon', (None, 9, 12, 12, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 34}), back=ic('StInvited'), transparent=True, visible=False),
  button('SwapButton', (None, 4, 22, 22, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 6}), '', 'rpl_swap', style='secondary', children=[iconp('SwapIcon', (5, 5, 12, 12), 'IconSwap')], visible=False),
  button('HomeButton', (None, 4, 22, 22, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 6}), '', 'rpl_home', style='pink', children=[iconp('HomeIcon', (5, 5, 12, 12), 'IconHome')], visible=False),
  button('RetryButton', (None, 4, 22, 22, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 6}), '', 'rpl_retry', style='secondary', children=[iconp('RetryIcon', (5, 5, 12, 12), 'IconPlus')], visible=False),
  button('KickButton', (None, 4, 22, 22, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 6}), '', 'rpl_kick', style='danger', children=[iconp('KickIcon', (5, 5, 12, 12), 'IconKick')], visible=False),
]
slots = [panel(f'Slot{k+1}', (6, 34 + k*34, None, 30, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 6}), children=slot_children) for k in range(6)]
gh = button('GroupHeader', (6, 6, None, 24, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 6}), 'Группа 1', 'rpl_group', style='ghost', alignx='left', size=12,
            children=[value('GroupCount', (None, 0, 48, 24, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 6}), size=12, color=DIM, alignx='right')])
groups = [panel(f'Group{i+1}', (i*214, 0, 206, 240), back=lay('group'), children=[gh] + slots) for i in range(4)]
GROUPS = panel('Groups', (14, 188, None, 240, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 14}), pick=True, children=groups)

HEADER = panel('Header', (1, 1, None, 43, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 1}), back=lay('header'), children=[
  panel('AccentMark', (13, 16, 10, 10), back=lay('mark'), transparent=True),
  text('TitleText', (31, 0, 160, 43), 'RaidPartyLeader', font=FONT_TITLE, size=15),
  panel('ModeChip', (186, 10, 190, 24), back=lay('chip'), transparent=True, children=[value('ModeText', (0, 0, 190, 24), size=12, color='0xffbdb4c4', alignx='center')]),
  # колокольчик: показывать ли уведомления (значок меняет Lua: BELL_ON / BELL_OFF)
  button('BellButton', (None, 7, 28, 28, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 39}), '', 'rpl_bell', style='ghost', children=[iconp('BellIcon', (6, 6, 16, 16), 'IconBell')]),
  button('CloseButton', (None, 7, 28, 28, {'ax': 'WIDGET_ALIGN_HIGH', 'hx': 7}), '', 'rpl_close', style='ghost', children=[iconp('CloseIcon', (7, 7, 14, 14), 'IconClose')]),
])
TABS = panel('Tabs', (0, 45, None, 37, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), pick=True, children=[
  button('TabCurrent', (14, 4, 90, 32), 'Текущее', 'rpl_tab_current', style='ghost', children=[panel('TabCurrentLine', (0, 30, 90, 2), back=lay('accent'), transparent=True)]),
  button('TabSaved', (108, 4, 150, 32), 'Сохранённые', 'rpl_tab_saved', style='ghost', children=[panel('TabSavedLine', (0, 30, 150, 2), back=lay('accent'), transparent=True, visible=False)]),
  button('TabQuick', (262, 4, 100, 32), 'Быстрое', 'rpl_tab_quick', style='ghost', children=[panel('TabQuickLine', (0, 30, 100, 2), back=lay('accent'), transparent=True, visible=False)]),
  panel('TabsLine', (0, 36, None, 1, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), back=lay('line'), transparent=True),
])
HEADER_LINE = panel('HeaderLine', (0, 44, None, 1, {'ax': 'WIDGET_ALIGN_BOTH', 'hx': 0}), back=lay('line'), transparent=True)
