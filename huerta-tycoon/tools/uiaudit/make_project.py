"""Writes <game>/uiaudit.project.json = default.project.json + audit scripts + autotest marker."""
import json, sys, os
game = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
p = json.load(open(os.path.join(game, "default.project.json"), encoding="utf-8"))
t = p["tree"]
t.setdefault("ServerScriptService", {"$className": "ServerScriptService"})["__UiAuditEnd"] = {"$path": here + "/UiAuditEnd.server.luau"}
spc = t.setdefault("StarterPlayer", {"$className": "StarterPlayer"}).setdefault("StarterPlayerScripts", {"$className": "StarterPlayerScripts"})
spc["__UiAudit"] = {"$path": here + "/UiAudit.client.luau"}
t.setdefault("ServerStorage", {"$className": "ServerStorage"})["__AutoTest"] = {"$className": "BoolValue"}
json.dump(p, open(os.path.join(game, "uiaudit.project.json"), "w", encoding="utf-8"), indent=2)
print("ok")
