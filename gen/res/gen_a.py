import os, sys, io, zlib, struct
sys.path.insert(0, os.environ.get('RPL_GEN') or os.path.expanduser('~/rplgen'))
from PIL import Image, ImageDraw
from tex import *

ROOT = os.environ.get('RPL_ROOT') or os.path.expanduser('~/mnt/Mods/Addons/RaidPartyLeader')
ASSETS = os.environ.get('RPL_ASSETS') or os.path.expanduser('~/mnt/AddonUIBuilder/assets/Interface')
assert os.environ.get('RPL_ROOT') or not os.path.exists(os.path.join(ROOT, 'AddonDesc.(UIAddon).xdb')), 'already exists'
for d in ('Widgets', 'Texts', 'Scripts'): os.makedirs(os.path.join(ROOT, d), exist_ok=True)
T = Tex(ROOT)

def wtext(rel, text):
    p = os.path.join(ROOT, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(b'\xff\xfe' + text.encode('utf-16-le'))
def wxml(rel, text):
    p = os.path.join(ROOT, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8', newline='\n').write(text)

ACC = '#BB1ABD'
BIG = {'WindowFrame', 'DialogFrame'}
def frame(name, w, h, r, fill, border=None, bw=1, dashed=False, cut=None, alpha_fill=None):
    c = cut or max(r, 4)
    w = h = 128 if name in BIG else 64
    return T.save(name, rrect(w, h, r, fill, border, bw, dashed, alpha_fill), stretch=True, frame=(c, c, c, c))

L = {}
L['window'] = frame('WindowFrame', 32, 32, 10, '#17141B', '#3A2F42', cut=12)['frame']
def rtop(w, h, r, fill):
    img = Image.new('RGBA', (w*S, h*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w*S-1, h*S-1], radius=r*S, fill=rgba(fill), corners=(True, True, False, False))
    return img.resize((w, h), Image.LANCZOS)
L['header'] = T.save('HeaderBack', rtop(128, 64, 9, '#1D1922'), stretch=True, frame=(10, 10, 10, 10))['frame']
L['cursor'] = T.save('Cursor', solid(4, 4, '#ECE6EF'))['stretch']
L['selection'] = T.save('Selection', solid(4, 4, '#BB1ABD', 110))['stretch']
L['line'] = T.save('Line', solid(4, 4, '#2A2330'))['stretch']
L['accent'] = T.save('AccentFill', solid(4, 4, ACC[1:]))['stretch']
L['mark'] = T.save('AccentMark', rrect(16, 16, 4, ACC))['stretch']
L['panel'] = frame('PanelFrame', 32, 32, 8, '#1F1A24', '#352C3C')['frame']
L['panelWarn'] = frame('PanelFrameWarn', 32, 32, 8, '#1F1A24', '#6A5420')['frame']
L['group'] = frame('GroupFrame', 32, 32, 8, '#1C1821', '#2C2532')['frame']
L['chip'] = frame('ChipFrame', 32, 32, 12, '#26202C', '#352C3C', cut=11)['frame']
L['slot'] = frame('SlotNormal', 32, 32, 6, '#231E28', '#2E2735')['frame']
L['slotHover'] = frame('SlotHover', 32, 32, 6, '#2B2531', '#3A3141')['frame']
L['slotSel'] = frame('SlotSelected', 32, 32, 6, '#4A1E4D', ACC)['frame']
L['slotMis'] = frame('SlotMisplaced', 32, 32, 6, '#2A1C27', '#6A3A5E')['frame']
L['slotEmpty'] = frame('SlotEmpty', 32, 32, 6, None, '#3A3141', dashed=True)['frame']
L['slotTarget'] = frame('SlotTarget', 32, 32, 6, None, ACC, dashed=True)['frame']
for kind, n, hv, pr, ds in [('Accent', ACC, '#C93ACB', '#8C148E', '#3A3340'), ('Secondary', '#2A2230', '#342B3B', '#211B26', '#1F1A24'),
                            ('Danger', '#2B161C', '#371C24', '#22111A', '#1F1A24'), ('Pink', '#2E1828', '#3A2033', '#24121F', '#1F1A24')]:
    bd = {'Accent': '#D45FD6', 'Secondary': '#4A3B52', 'Danger': '#6A2A3A', 'Pink': '#6A3A5E'}[kind]
    L['btn'+kind] = frame(f'Btn{kind}Normal', 32, 32, 7, n, bd)['frame']
    L['btn'+kind+'Hover'] = frame(f'Btn{kind}Hover', 32, 32, 7, hv, bd)['frame']
    L['btn'+kind+'Pressed'] = frame(f'Btn{kind}Pressed', 32, 32, 7, pr, bd)['frame']
    L['btn'+kind+'Disabled'] = frame(f'Btn{kind}Disabled', 32, 32, 7, ds, '#2C2532')['frame']
L['ghost'] = T.save('Transparent', solid(4, 4, '#000000', 0))['stretch']
L['ghostHover'] = frame('GhostHover', 32, 32, 6, '#FFFFFF', None, alpha_fill=18)['frame']
L['field'] = frame('FieldFrame', 32, 32, 7, '#100E13', '#3A3141')['frame']
L['toast'] = frame('ToastFrame', 32, 32, 8, '#2A2230', '#4A3B52')['frame']
L['dialog'] = frame('DialogFrame', 32, 32, 12, '#1A161E', '#3A2F42', cut=13)['frame']
L['dim'] = T.save('DimBack', solid(4, 4, '#08060A', 158))['stretch']
for k, fg, bg, bd in [('Party', '#9CCBFF', '#142334', '#24415F'), ('Raid', '#FFA45C', '#331E10', '#634020'), ('Small', '#F5D25A', '#2E2810', '#5A4C18')]:
    L['chip'+k] = frame(f'Chip{k}', 32, 32, 5, bg, bd)['frame']

def pill(fill, border, alpha_border=72):
    img = Image.new('RGBA', (64*S, 32*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([0,0,64*S-1,32*S-1], radius=16*S, fill=rgba(border, alpha_border))
    d.rounded_rectangle([S,S,64*S-1-S,32*S-1-S], radius=15*S, fill=rgba(fill))
    return img.resize((64,32), Image.LANCZOS)
L['rpl'] = T.save('RplNormal', pill(ACC, '#FFFFFF'))['stretch']
L['rplHover'] = T.save('RplHover', pill('#C231C4', '#FFFFFF', 110))['stretch']
L['rplPressed'] = T.save('RplPressed', pill('#8C148E', '#FFFFFF', 46))['stretch']
L['rplDisabled'] = T.save('RplDisabled', pill('#3A3340', '#FFFFFF', 26))['stretch']
L['badge'] = T.save('BadgeDot', circle(16, '#F5B841', '#101218', 2))['stretch']
# индикатор состояния на кнопке RPL: зелёный — всё как сохранено, жёлтый — сбор/отличия, красный — не сохранено
T.save('DotOk', circle(16, '#3DDC84', '#101218', 2), stretch=True, element=True)
T.save('DotWarn', circle(16, '#F5B841', '#101218', 2), stretch=True, element=True)
T.save('DotBad', circle(16, '#F0475A', '#101218', 2), stretch=True, element=True)
# «Окно открыто»: вокруг кнопки тёмный зазор и кольцо акцента 60% (как в прототипе).
# Радиус в пикселях окна: высота кольца 40 * масштаб / 2.
_K = float(os.environ.get('RPL_SCALE', '1.2'))
def ring_img(size, r, outer, inner):
    img = Image.new('RGBA', (size*S, size*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size*S-1, size*S-1], radius=r*S, fill=rgba(ACC, 153))
    o = outer; d.rounded_rectangle([o*S, o*S, size*S-1-o*S, size*S-1-o*S], radius=(r-o)*S, fill=rgba('#16131A'))
    o2 = outer + inner; d.rounded_rectangle([o2*S, o2*S, size*S-1-o2*S, size*S-1-o2*S], radius=max(0, r-o2)*S, fill=(0, 0, 0, 0))
    return img.resize((size, size), Image.LANCZOS)
_RK = _K * 0.8  # кнопка RPL на 20% меньше
_R = int(20 * _RK + 0.5)
L['rplRing'] = T.save('RplRing', ring_img(64, _R, max(1, int(2*_RK+0.5)), max(1, int(2*_RK+0.5))), stretch=True, frame=(_R, _R, _R, _R))['frame']

ICONS = {
 'IconCrown': ('#F5C04A', dict(polys=[CROWN], lines=[[(3,13.5),(13,13.5)]], width=1.6)),
 'IconStar': ('#8EC5FF', dict(polys=[STAR])),
 'IconBag': ('#7FDCA0', dict(polys=[BAG, [(6,2.5),(10,2.5),(9,5),(7,5)]], lines=[[(8,8),(8,11.5)], [(6.8,9.2),(9.2,9.2)]])),
 'IconKick': ('#FFB3C0', dict(circles=[(6.5,5,2.5,False)], lines=[[(2,13.5),(2.6,11.4),(4.2,10),(6.5,9.5),(8.8,10),(10.4,11.4),(11,13.5)], [(11,6),(14,9)], [(14,6),(11,9)]])),
 'IconSwap': ('#F2B8F3', dict(lines=[[(2.5,5.5),(12.5,5.5)], [(10,3),(12.5,5.5),(10,8)], [(13.5,10.5),(3.5,10.5)], [(6,8),(3.5,10.5),(6,13)]], width=1.8)),
 'IconHome': ('#FF8FD0', dict(lines=[[(8,2),(8,10)], [(4.5,6.5),(8,10),(11.5,6.5)], [(3,13.5),(13,13.5)]], width=1.8)),
 'IconPlus': ('#F2B8F3', dict(lines=[[(8,3),(8,13)], [(3,8),(13,8)]], width=2)),
 'IconRetry': ('#F2B8F3', dict(lines=[arc(8,8.5,5,-50,250), [(13,2.5),(12.4,6.6),(8.6,5.6)]], width=1.8)),
 'IconClose': ('#BDB4C4', dict(lines=[[(3.5,3.5),(12.5,12.5)], [(12.5,3.5),(3.5,12.5)]], width=1.9)),
 'IconLink': ('#E58BE7', dict(lines=[[(6.2,9.8),(9.8,6.2)], [(7,4.6)] + arc(10.3,5.7,2.9,-150,120)[1:] + [(11.4,9)], [(9,11.4)] + arc(5.7,10.3,2.9,30,300)[1:] + [(4.6,7)]], width=1.6)),
 'IconBack': ('#DCD4E2', dict(lines=[[(9.7,3.4),(5.1,8),(9.7,12.6)]], width=2)),
 'IconRename': ('#A79DAE', dict(polys=[[(10.5,2.5),(13.5,5.5),(6,13),(3,13),(3,10)]])),
 'IconDelete': ('#A79DAE', dict(lines=[[(2.5,4),(13.5,4)], [(6,4),(6,2.5),(10,2.5),(10,4)], [(4,4),(4.7,13.5),(11.3,13.5),(12,4)], [(6.6,6.5),(6.6,11)], [(9.4,6.5),(9.4,11)]])),
 'IconFlag': ('#FF8FD0', dict(lines=[[(4,14.6),(4,2)]], fills=[[(4,2.6),(12.7,2.6),(10.7,5.6),(12.7,8.7),(4,8.7)]], width=1.7)),
 'StInvited': ('#F5B841', dict(circles=[(8,8,6.1,False)], lines=[[(8,4.8),(8,8),(10.3,9.6)]], width=2)),
 'StDeclined': ('#F0607A', dict(lines=[[(4,4),(12,12)], [(12,4),(4,12)]], width=2.6)),
 'StFailed': ('#FF9F5A', dict(polys=[[(8,2),(14.7,14),(1.3,14)]], lines=[[(8,6.7),(8,9.9)]], circles=[(8,12,0.9,True)], width=2)),
 'StOffline': ('#9AA0AC', dict(circles=[(8,8,6.1,False)], lines=[[(4.7,11.3),(11.3,4.7)]], width=2)),
 'StReady': ('#7FDCA0', dict(lines=[[(3,8.5),(6.5,12),(13,4.5)]], width=2.6)),
 'IconReady': ('#9BE89B', dict(circles=[(8,8,6.1,False)], lines=[[(5,8.3),(7.3,10.6),(11.2,5.8)]], width=1.8)),
 'StStranger': ('#F5B841', dict(circles=[(5.5,5,2.5,False), (12.2,12.6,0.9,True)], lines=[[(1.2,13.5),(1.8,11.4),(3.4,10),(5.5,9.5),(7.6,10),(9.2,11.4),(9.8,13.5)], [(10.2,4.2),(10.8,3),(12.2,2.4),(13.6,3),(14.1,4.3),(13.6,5.6),(12.2,6.6),(12.2,9.6)]], width=1.7)),
 'StMissing': ('#B9A6FF', dict(circles=[(6.5,5,2.5,False)], lines=[[(2,13.5),(2.6,11.4),(4.2,10),(6.5,9.5),(8.8,10),(10.4,11.4),(11,13.5)], [(10.5,7.5),(14.5,7.5)]], width=1.8)),
}
for name, (col, kw) in ICONS.items():
    T.save(name, icon(32, col, **kw), stretch=True, element=True)
ck = Image.new('RGBA', (32*S, 32*S), (0,0,0,0)); d = ImageDraw.Draw(ck)
d.rounded_rectangle([2*S, 2*S, 30*S, 30*S], radius=6*S, fill=rgba(ACC)); d.line([(9*S,16*S),(14*S,21*S),(23*S,11*S)], fill=(255,255,255,255), width=4*S, joint='curve')
T.save('CheckOn', ck.resize((32,32), Image.LANCZOS), element=True)
co = Image.new('RGBA', (32*S, 32*S), (0,0,0,0)); d = ImageDraw.Draw(co)
d.rounded_rectangle([2*S, 2*S, 30*S, 30*S], radius=6*S, fill=rgba('#8C8393')); d.rounded_rectangle([5*S, 5*S, 27*S, 27*S], radius=4*S, fill=rgba('#100E13'))
T.save('CheckOff', co.resize((32,32), Image.LANCZOS), element=True)
KNOT = [(6,2.5),(10,2.5),(9,5),(7,5)]
T.save('BadgeLeader', icon(32, '#F5C04A', polys=[[(x*0.62+3, y*0.62+3) for x, y in CROWN]], lines=[[(4.6,10.8),(11.4,10.8)]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)
T.save('BadgeAssist', icon(32, '#8EC5FF', polys=[[(x*0.62+3, y*0.62+3) for x, y in STAR]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)
SHIELD = [(8,1.8),(13.6,3.6),(13.2,8.6),(8,14.4),(2.8,8.6),(2.4,3.6)]
T.save('BadgeLeague', icon(32, '#5AA2FF', polys=[[(x*0.62+3, y*0.62+3) for x, y in SHIELD]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)
T.save('BadgeEmpire', icon(32, '#FF5A4E', polys=[[(x*0.62+3, y*0.62+3) for x, y in SHIELD]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)
T.save('BadgeFaction', icon(32, '#BDB4C4', polys=[[(x*0.62+3, y*0.62+3) for x, y in SHIELD]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)
T.save('BadgeLoot', icon(32, '#7FDCA0', polys=[[(x*0.62+3, y*0.62+3) for x, y in BAG], [(x*0.62+3, y*0.62+3) for x, y in KNOT]], width=1.4, bg=('#4A3B52', '#17141B')), element=True)

def decode_bin(path, fmt, size):
    raw = zlib.decompress(open(path, 'rb').read())[8:]
    head = b'DDS ' + struct.pack('<7I', 124, 0x1|0x2|0x4|0x1000|0x80000, size, size, len(raw), 0, 0) + b'\0'*44
    head += struct.pack('<2I4s5I', 32, 0x4, fmt, 0,0,0,0,0) + struct.pack('<5I', 0x1000, 0,0,0,0)
    return Image.open(io.BytesIO(head + raw)).convert('RGBA')
CI = os.path.join(ASSETS, 'Common', 'Elements', 'ClassIcons')
classes = [('BARD','Bard'), ('DRUID','Druid'), ('ENGINEER','Engineer'), ('MAGE','Mage'), ('NECROMANCER','Necromancer'), ('PALADIN','Paladin'),
           ('PRIEST','Priest'), ('PSIONIC','Psionic'), ('STALKER','Stalker'), ('WARLOCK','Warlock'), ('WARRIOR','Warrior')]
for key, f in classes:
    T.save(f'Class{f}', decode_bin(os.path.join(CI, f'{f}.(UITexture).bin'), b'DXT5', 256).resize((64, 64), Image.LANCZOS), element=True)
unk = Image.new('RGBA', (64*S, 64*S), (0,0,0,0)); d = ImageDraw.Draw(unk)
d.rounded_rectangle([6*S, 6*S, 58*S, 58*S], radius=10*S, fill=rgba('#3A3340'))
d.line(arc(32*S, 25*S, 9*S, 180, 400, 30) + [(32*S, 38*S)], fill=rgba('#E2DBE7'), width=6*S, joint='curve'); d.ellipse([29*S, 44*S, 35*S, 50*S], fill=rgba('#E2DBE7'))
T.save('ClassUnknown', unk.resize((64, 64), Image.LANCZOS), element=True)
AS = os.path.join(ASSETS, 'Icons', 'CommonState')
aspects = [('TANK','Tank'), ('HEAL','Heal'), ('SUPPORT','Buff'), ('DAMAGE','Damage')]
for key, f in aspects:
    T.save(f'Aspect{f}', decode_bin(os.path.join(AS, f'Aspect_{f}.(UITexture).bin'), b'DXT1', 64), element=True)
G_CLASSES = T.group('Classes', [(k, f'Class{f}') for k, f in classes] + [('UNKNOWN', 'ClassUnknown')])
G_ASPECTS = T.group('Aspects', [(k, f'Aspect{f}') for k, f in aspects])
# точки цвета ценности (цвета — из документации ITEM_QUALITY_...)
QUALITY_COLORS = [('JUNK', '#999999'), ('GOODS', '#DCDCDC'), ('COMMON', '#00E526'), ('UNCOMMON', '#2080FF'),
                  ('RARE', '#C040FF'), ('EPIC', '#FF8000'), ('LEGENDARY', '#00FFD2'), ('RELIC', '#E0FF40')]
for _q, _c in QUALITY_COLORS:
    T.save(f'Quality{_q.title()}', circle(16, _c, '#101218', 1), stretch=True, element=True)
G_ICONS = T.group('Icons', [(f'Q_{_q}', f'Quality{_q.title()}') for _q, _c in QUALITY_COLORS] + [('DOT_OK','DotOk'), ('DOT_WARN','DotWarn'), ('DOT_BAD','DotBad'), ('INVITED','StInvited'), ('DECLINED','StDeclined'), ('FAILED','StFailed'), ('OFFLINE','StOffline'), ('MISSING','StMissing'), ('STRANGER','StStranger'), ('READY','StReady'), ('FAC_LEAGUE','BadgeLeague'), ('FAC_EMPIRE','BadgeEmpire'), ('FAC_OTHER','BadgeFaction'), ('MISPLACED','IconFlag'),
                             ('CHECK_ON','CheckOn'), ('CHECK_OFF','CheckOff')])
def lay(key): return 'Textures/' + L[key]
def ic(name): return 'Textures/' + T.made[name]['stretch']
