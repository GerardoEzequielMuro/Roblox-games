import re,sys
p='src/shared/Config.luau'
s=open(p,encoding='utf-8').read()
args=dict(a.split('=') for a in sys.argv[1:])
for k,v in args.items():
    if k.startswith("z"):
        s=re.sub(r'(\{ index = %s,[^\n]*?cost = )\d+'%k[1:], lambda m:m.group(1)+v, s)
    elif k=='rb': s=re.sub(r'Config.RebirthBaseCost = \d+','Config.RebirthBaseCost = '+v,s)
    elif k=='rg': s=re.sub(r'Config.RebirthCostGrowth = [\d.]+','Config.RebirthCostGrowth = '+v,s)
    else:
        s=re.sub(r'(\{ id = "%s",[^\n]*?price = )\d+'%k, lambda m:m.group(1)+v, s)
open(p,'w',encoding='utf-8').write(s)
