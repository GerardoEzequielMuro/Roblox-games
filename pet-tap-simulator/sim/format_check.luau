local Format = require("../src/shared/Format")
for _, n in { 0, 999, 1000, 1500, 100000, 123456, 1e6, 2.5e9, 6e9, 1e15 } do print(n, Format.abbrev(n)) end
for _, p in { 60, 8.999, 2.399, 0.1, 0.019, 0.001 } do print(p, Format.chance(p)) end
print(Format.commas(1234567), Format.time(3725))
