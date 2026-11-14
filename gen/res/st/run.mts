import {readFile} from 'node:fs/promises';
const src = process.env.HOME + '/mnt/AddonUIBuilder/apps/desktop/src/addonTree.ts';
const T: any = await import(src);
const folder = process.env.HOME + '/mnt/Mods/Addons/RaidPartyLeader';
const read = async (p: string) => { try { const b = await readFile(p); if (b[0]===0xff && b[1]===0xfe) return b.toString('utf16le').slice(1); return b.toString('utf8'); } catch { return null; } };
const doc = await T.loadAddon(folder, read);
console.log('nodes', doc.nodes.size, 'warnings', doc.warnings.length);
for (const w of doc.warnings.slice(0, 25)) console.log(' W', w);
const rects = T.layout(doc, 1920, 1080);
let shown = 0; for (const [k, r] of rects) { if (/RPLWindow$|RPLButton$|Group4$|SaveDialog$|DialogPanel$|Toast$/.test(k)) { console.log(k, JSON.stringify(r)); if (++shown > 12) break; } }
const keys = [...rects.keys()]; console.log('rects', keys.length, keys.slice(0,3));
for (const [id, n] of doc.nodes) { const nm = (n as any).name; if (['RPLWindow','RPLButton','SaveDialog','DialogPanel','Toast','Group4','StartInviteButton','SavedRow'].includes(nm)) console.log(nm, (n as any).type, JSON.stringify(rects.get(id))); }
