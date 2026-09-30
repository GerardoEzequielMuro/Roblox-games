"""Every translation key the code uses must exist in en.luau (run from the repo root)."""
import re, glob, sys
en = open('src/shared/Locales/en.luau', encoding='utf-8').read()
keys = set(re.findall(r'\["([^"]+)"\]\s*=', en))
used = set()
for f in glob.glob('src/**/*.luau', recursive=True):
    if 'Locales' in f:
        continue
    s = open(f, encoding='utf-8').read()
    for m in re.finditer(r'(?:Lang\.t\(|Key = |\bM\(|Locale\.m\(|LocKey", |sign\([^"\n]*?|section\([^"\n]*?)"([a-z_]+\.[A-Za-z0-9_.]+)"', s):
        used.add(m.group(1))
    for m in re.finditer(r'return false, "(msg\.[a-z_]+)"', s):
        used.add(m.group(1))
missing = sorted(k for k in used if k not in keys and not k.endswith('.'))
print(f"{len(used)} literal keys used, {len(keys)} keys in en")
for k in missing:
    print("MISSING", k)
sys.exit(1 if missing else 0)
