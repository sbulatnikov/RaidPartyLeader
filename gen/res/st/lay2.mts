import {readFile} from 'node:fs/promises';
const T: any = await import(process.env.HOME + '/mnt/AddonUIBuilder/apps/desktop/src/addonTree.ts');
const folder = process.env.HOME + '/mnt/Mods/Addons/RaidPartyLeader';
const read = async (p: string) => { try { const b = await readFile(p); if (b[0]===0xff && b[1]===0xfe) return b.toString('utf16le').slice(1); return b.toString('utf8'); } catch { return null; } };
const doc = await T.loadAddon(folder, read);
console.log('nodes', doc.nodes.size, 'warnings', doc.warnings.length, doc.warnings.slice(0,5));
const rects = T.layout(doc, 1920, 1080);
const want = ['RPLHost','RPLButton','RPLRing','RPLBadge','PlaceAllButton','AutoRetryCheck','AutoRetryLabel','AutoRetryIcon','Footer'];
for (const [id, n] of doc.nodes) { const nm = (n as any).name; if (want.includes(nm)) console.log(nm.padEnd(16), JSON.stringify(rects.get(id))); }
let c=0; for (const [id, n] of doc.nodes) { const nm=(n as any).name; if (['Group1','SlotButton','NameText','SwapButton'].includes(nm) && c<6) { console.log(nm.padEnd(16), JSON.stringify(rects.get(id))); c++; } }
