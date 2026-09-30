"""Minimal stdio MCP client for Roblox Studio's built-in MCP server (StudioMCP.exe).

Usage:
  python studio_mcp.py tools
  python studio_mcp.py call <tool> '<json args>'
"""
import glob
import json
import os
import subprocess
import sys
import threading
import queue


def find_exe() -> str:
    hits = glob.glob(os.path.expandvars(r"%LOCALAPPDATA%\Roblox\Versions\*\StudioMCP.exe"))
    if not hits:
        sys.exit("StudioMCP.exe not found")
    return max(hits, key=os.path.getmtime)


class Client:
    def __init__(self):
        self.p = subprocess.Popen([find_exe()], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.q: "queue.Queue[dict]" = queue.Queue()
        self.id = 0
        threading.Thread(target=self._reader, daemon=True).start()
        threading.Thread(target=self._err, daemon=True).start()
        self.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "cli", "version": "1"}})
        self.notify("notifications/initialized", {})

    def _reader(self):
        for line in self.p.stdout:
            line = line.strip()
            if line:
                try:
                    self.q.put(json.loads(line))
                except json.JSONDecodeError:
                    sys.stderr.write("[stdout] " + line.decode(errors="replace") + "\n")

    def _err(self):
        for line in self.p.stderr:
            if os.environ.get("MCP_DEBUG"):
                sys.stderr.write("[mcp] " + line.decode(errors="replace"))

    def _send(self, msg: dict):
        self.p.stdin.write((json.dumps(msg) + "\n").encode())
        self.p.stdin.flush()

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params, timeout=180):
        self.id += 1
        rid = self.id
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            msg = self.q.get(timeout=timeout)
            if msg.get("id") == rid:
                return msg


def main():
    c = Client()
    if sys.argv[1] == "tools":
        r = c.request("tools/list", {})
        for t in r["result"]["tools"]:
            print("==", t["name"], "::", t.get("description", "")[:300].replace("\n", " "))
            print("   args:", json.dumps(t.get("inputSchema", {}).get("properties", {}))[:600])
    elif sys.argv[1] == "call":
        args = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
        if len(sys.argv) > 4:  # 4th arg: file whose content goes into args["code"]
            args["code"] = open(sys.argv[4], encoding="utf-8").read()
        r = c.request("tools/call", {"name": sys.argv[2], "arguments": args}, timeout=600)
        res = r.get("result") or r
        for item in res.get("content", []) if isinstance(res, dict) else []:
            if item.get("type") == "text":
                print(item["text"])
            elif item.get("type") == "image":
                import base64
                out = os.environ.get("MCP_IMG", "capture.png")
                open(out, "wb").write(base64.b64decode(item["data"]))
                print("image ->", out)
        if not isinstance(res, dict) or "content" not in res:
            print(json.dumps(res)[:3000])
    c.p.terminate()


if __name__ == "__main__":
    main()
