#!/usr/bin/env python3
"""Exercise every ClickCast control-server route. Run with the app running (or run in place from Bash)."""
import json, sys, urllib.request
BASE = "http://127.0.0.1:8766"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # never go through a proxy for loopback

def call(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method="POST" if data else "GET")
    with opener.open(req, timeout=3) as r:
        return json.load(r)

def check(label, cond):
    print(("PASS " if cond else "FAIL ") + label)
    return cond

ok = True
s = call("/state")
ok &= check("state has keys", all(k in s for k in ("paused","cursorSize","highlightHex","options")))
before = s["clickRipples"]
ok &= check("toggle ripples", call("/toggle", {"key":"clickRipples"})["clickRipples"] == (not before))
ok &= check("set ripples on", call("/toggle", {"key":"clickRipples","on":True})["clickRipples"] is True)
ok &= check("choose size value", call("/choose", {"key":"cursorSize","value":"large"})["cursorSize"] == "large")
ok &= check("cycle size +2 wraps", call("/choose", {"key":"cursorSize","step":2})["cursorSize"] == "small")
ok &= check("cycle size -1 wraps", call("/choose", {"key":"cursorSize","step":-1})["cursorSize"] == "huge")
ok &= check("choose color", call("/choose", {"key":"highlightColor","value":"pink"})["highlightHex"] == "#FF66B3")
ok &= check("choose position", call("/choose", {"key":"hudPosition","value":"topCenter"})["hudPosition"] == "topCenter")
ok &= check("pause toggle", call("/pause", {"toggle":True})["paused"] is True)
ok &= check("unpause", call("/pause", {"paused":False})["paused"] is False)
ok &= check("message", call("/message", {"text":"hello","seconds":1})["running"] is True)
ok &= check("bad route errors", "error" in call("/nope"))
ok &= check("bad key errors", "error" in call("/toggle", {"key":"zzz"}))
# restore defaults
call("/choose", {"key":"cursorSize","value":"medium"}); call("/choose", {"key":"highlightColor","value":"yellow"}); call("/choose", {"key":"hudPosition","value":"bottomCenter"})
print("ALL PASS" if ok else "SOME FAILED"); sys.exit(0 if ok else 1)
