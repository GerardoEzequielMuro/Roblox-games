# Lists every translation key the code uses (literal ones) and the dynamic prefixes.
# Usage: python tests/scan_keys.py [--check]   (--check compares with Locales/en.luau)
import re, sys, glob, io
lit=set(); dyn=set()
pat=re.compile(r'(?:Lang\.t|Lang\.msg|Locale\.t\([^,]+,|\bM|Locale\.m|Lang\.bind\([^,]+,)\s*\(?\s*(?:if [^"]*? then )?"([a-zA-Z_][\w.]*)"(\s*\.\.)?')
key=re.compile(r'\bKey = "([\w.]+)"(\s*\.\.)?')
loc=re.compile(r'Loc\w+ = "([\w.]+)"(\s*\.\.)?')
alt=re.compile(r'(?:then|else)\s+"((?:msg|toast|hud|pets|capsule|relics|rebirth|teleport|auto|pvp|world|announce|tutorial|upgrades|index|store|rewards|quests|settings|invite|reward|planet|tools|offline|starter|notif|group|ads|event|prompt)\.[\w.]+)"(\s*\.\.)?')
for f in glob.glob('src/**/*.luau',recursive=True):
    if 'Locales' in f: continue
    s=io.open(f,encoding='utf-8').read()
    for rx in (pat,key,loc,alt):
        for m in rx.finditer(s):
            (dyn if m.group(2) else lit).add(m.group(1))
if '--check' in sys.argv:
    en=io.open('src/shared/Locales/en.luau',encoding='utf-8').read()
    keys=set(re.findall(r'\["([\w.]+)"\]\s*=',en))
    missing=sorted(k for k in lit if k not in keys)
    print('literal keys used: %d, missing in en: %d'%(len(lit),len(missing)))
    for k in missing: print('  MISSING',k)
    for d in sorted(dyn):
        if not any(k.startswith(d) for k in keys): print('  NO KEY WITH PREFIX',d)
    sys.exit(1 if missing else 0)
print('\n'.join(sorted(lit)))
print('--- dynamic prefixes')
print('\n'.join(sorted(dyn)))
