# Texture drawing + UITexture writer for RaidPartyLeader
import os, io, zlib, struct
from PIL import Image, ImageDraw

def rgba(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), a)

from dxt import encode_dxt5
def dds_payload(img):
    return encode_dxt5(img)

class Tex:
    def __init__(self, root):
        self.root = root; self.dir = os.path.join(root, 'Widgets', 'Textures'); os.makedirs(self.dir, exist_ok=True)
        self.made = {}
    def w(self, name, text):
        open(os.path.join(self.dir, name), 'w', encoding='utf-8', newline='\n').write(text)
    def save(self, name, img, stretch=True, frame=None, element=False):
        w, h = img.size
        assert w & (w-1) == 0 and h & (h-1) == 0, (name, img.size)
        payload = dds_payload(img)
        assert len(payload) == (w//4)*(h//4)*16, (name, len(payload))
        binary = zlib.compress(struct.pack('<II', 0, len(payload)) + payload, 9)
        open(os.path.join(self.dir, f'{name}.(UITexture).bin'), 'wb').write(binary)
        self.w(f'{name}.(UITexture).xdb', f'''<?xml version="1.0" encoding="UTF-8"?>
<UITexture>
  <mipSW>-1</mipSW>
  <mipsNumber>1</mipsNumber>
  <generateMipChain>false</generateMipChain>
  <type>DXT5</type>
  <width>{w}</width>
  <height>{h}</height>
  <realWidth>{w}</realWidth>
  <realHeight>{h}</realHeight>
  <disableLODControl>false</disableLODControl>
  <alphaTex>true</alphaTex>
  <binaryFileSize>{len(binary)}</binaryFileSize>
  <binaryFile href="{name}.(UITexture).bin" />
  <sourceFile href="" />
  <sourceFileCRC>0</sourceFileCRC>
  <wrap>false</wrap>
</UITexture>
''')
        self.w(f'{name}.Studio.(UISingleTexture).xdb', f'''<?xml version="1.0" encoding="UTF-8" ?>
<UISingleTexture>
\t<singleTexture href="{name}.(UITexture).xdb" />
</UISingleTexture>
''')
        layers = {}
        if stretch:
            self.w(f'{name}.Stretch.(WidgetLayerSimpleTexture).xdb', f'''<?xml version="1.0" encoding="UTF-8" ?>
<WidgetLayerSimpleTexture>
\t<Color>0xffffffff</Color>
\t<Grayed>false</Grayed>
\t<BlendEffect>BLEND_EFFECT_ALPHABLND</BlendEffect>
\t<flatPlacement>false</flatPlacement>
\t<textureItem href="{name}.Studio.(UISingleTexture).xdb" />
\t<Scaling>true</Scaling>
</WidgetLayerSimpleTexture>
''')
            layers['stretch'] = f'{name}.Stretch.(WidgetLayerSimpleTexture).xdb'
        if frame:
            L, R, T, B = frame
            fname = f'{name}.Frame_{L}_{R}_{T}_{B}.(WidgetLayerTiledTexture).xdb'
            self.w(fname, f'''<?xml version="1.0" encoding="UTF-8" ?>
<WidgetLayerTiledTexture>
\t<Color>0xffffffff</Color>
\t<Grayed>false</Grayed>
\t<BlendEffect>BLEND_EFFECT_ALPHABLND</BlendEffect>
\t<flatPlacement>false</flatPlacement>
\t<textureItem href="{name}.Studio.(UISingleTexture).xdb" />
\t<Layout>
\t\t<LeftX>{L}</LeftX>
\t\t<MiddleX>{w-L-R}</MiddleX>
\t\t<RightX>{R}</RightX>
\t\t<TopY>{T}</TopY>
\t\t<MiddleY>{h-T-B}</MiddleY>
\t\t<BottomY>{B}</BottomY>
\t</Layout>
</WidgetLayerTiledTexture>
''')
            layers['frame'] = fname
        if element:
            self.w(f'{name}.(UITextureElement).xdb', f'''<?xml version="1.0" encoding="UTF-8" ?>
<UITextureElement>
\t<singleTexture href="{name}.(UITexture).xdb#xpointer(/UITexture)" />
\t<permanentCache>0</permanentCache>
</UITextureElement>
''')
            layers['element'] = f'{name}.(UITextureElement).xdb'
        self.made[name] = layers
        return layers
    def group(self, gname, items):
        body = ''.join(f'\t\t<Item>\n\t\t\t<name>{k}</name>\n\t\t\t<textureItem href="{v}.(UITextureElement).xdb" />\n\t\t</Item>\n' for k, v in items)
        self.w(f'{gname}.(UIRelatedTextures).xdb', f'<?xml version="1.0" encoding="UTF-8" ?>\n<UIRelatedTextures>\n\t<Items>\n{body}\t</Items>\n</UIRelatedTextures>\n')
        return f'Widgets/Textures/{gname}.(UIRelatedTextures).xdb'

S = 4  # supersampling
def rrect(w, h, r, fill, border=None, bw=1, dashed=False, alpha_fill=None):
    img = Image.new('RGBA', (w*S, h*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    f = rgba(fill, alpha_fill if alpha_fill is not None else 255) if fill else None
    if border and not dashed:
        d.rounded_rectangle([0, 0, w*S-1, h*S-1], radius=r*S, fill=rgba(border))
        d.rounded_rectangle([bw*S, bw*S, w*S-1-bw*S, h*S-1-bw*S], radius=max(0,(r-bw))*S, fill=f if f else (0,0,0,0))
    else:
        if f: d.rounded_rectangle([0, 0, w*S-1, h*S-1], radius=r*S, fill=f)
        if border and dashed:
            mask = Image.new('L', (w*S, h*S), 0); md = ImageDraw.Draw(mask)
            md.rounded_rectangle([0, 0, w*S-1, h*S-1], radius=r*S, fill=255)
            md.rounded_rectangle([bw*S, bw*S, w*S-1-bw*S, h*S-1-bw*S], radius=max(0,(r-bw))*S, fill=0)
            dash = Image.new('L', (w*S, h*S), 0); dd = ImageDraw.Draw(dash)
            step = 6*S
            for x in range(0, w*S, step): dd.rectangle([x, 0, x+3*S, h*S], fill=255)
            for y in range(0, h*S, step): dd.rectangle([0, y, 5*S, y+3*S], fill=255); dd.rectangle([w*S-5*S, y, w*S, y+3*S], fill=255)
            from PIL import ImageChops
            m = ImageChops.multiply(mask, dash)
            col = Image.new('RGBA', (w*S, h*S), rgba(border)); img.paste(col, (0,0), m)
    return img.resize((w, h), Image.LANCZOS)

def solid(w, h, color, a=255):
    return Image.new('RGBA', (w, h), rgba(color, a))

def circle(size, fill, border=None, bw=1):
    img = Image.new('RGBA', (size*S, size*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    if border: d.ellipse([0,0,size*S-1,size*S-1], fill=rgba(border)); d.ellipse([bw*S,bw*S,size*S-1-bw*S,size*S-1-bw*S], fill=rgba(fill))
    else: d.ellipse([0,0,size*S-1,size*S-1], fill=rgba(fill))
    return img.resize((size,size), Image.LANCZOS)

def icon(size, color, lines=(), polys=(), fills=(), circles=(), width=1.6, vb=16, bg=None):
    k = size*S/vb
    img = Image.new('RGBA', (size*S, size*S), (0,0,0,0)); d = ImageDraw.Draw(img)
    if bg: d.ellipse([0,0,size*S-1,size*S-1], fill=rgba(bg[0])); d.ellipse([S,S,size*S-1-S,size*S-1-S], fill=rgba(bg[1]))
    col = rgba(color); lw = max(1, int(width*k))
    def P(pts): return [(x*k, y*k) for x, y in pts]
    for pts in fills: d.polygon(P(pts), fill=col)
    for pts in list(lines) + [list(p)+[p[0]] for p in polys]:
        pp = P(pts); d.line(pp, fill=col, width=lw, joint='curve')
        for x, y in (pp[0], pp[-1]): d.ellipse([x-lw/2, y-lw/2, x+lw/2, y+lw/2], fill=col)
    for cx, cy, r, filled in circles:
        if filled: d.ellipse([(cx-r)*k, (cy-r)*k, (cx+r)*k, (cy+r)*k], fill=col)
        else: d.ellipse([(cx-r)*k, (cy-r)*k, (cx+r)*k, (cy+r)*k], outline=col, width=lw)
    return img.resize((size,size), Image.LANCZOS)

import math
def arc(cx, cy, r, a0, a1, n=24):
    return [(cx + r*math.cos(math.radians(a0+(a1-a0)*i/n)), cy + r*math.sin(math.radians(a0+(a1-a0)*i/n))) for i in range(n+1)]

STAR = [(8,2),(9.8,5.9),(14,6.4),(10.9,9.3),(11.7,13.5),(8,11.4),(4.3,13.5),(5.1,9.3),(2,6.4),(6.2,5.9)]
BAG = [(7,5),(4.6,7),(3.3,9.5),(3,11.5),(3.6,13.3),(5.5,14),(10.5,14),(12.4,13.3),(13,11.5),(12.7,9.5),(11.4,7),(9,5)]
CROWN = [(3,11),(2,5),(5.5,8),(8,3),(10.5,8),(14,5),(13,11)]
