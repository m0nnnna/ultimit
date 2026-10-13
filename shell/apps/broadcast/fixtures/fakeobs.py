#!/usr/bin/env python3
"""fakeobs.py - a fake OBS Studio for BROADCAST_FAKE=1: obs-websocket v5 (with authentication) on
$BROADCAST_OBS_PORT (default 14455), loads the profile + scene collection BROADCAST generated and applies the
requests to it. State is mirrored to $BROADCAST_FAKE_STATE/obs-state.json. SIGTERM = clean quit.
argv: the OBS flags (--profile NAME --collection NAME --scene NAME --startvirtualcam ...)."""
import asyncio, base64, hashlib, json, os, secrets, signal, sys

HERE = os.path.dirname(os.path.abspath(__file__))
S = os.environ["BROADCAST_FAKE_STATE"]
HOME = os.environ.get("BROADCAST_HOME") or os.path.join(S, "home")
PORT = int(os.environ.get("BROADCAST_OBS_PORT") or 14455)
CFG = os.path.join(HOME, ".var/app/com.obsproject.Studio/config/obs-studio")


def arg(flag):
    a = sys.argv[1:]
    return a[a.index(flag) + 1] if flag in a and a.index(flag) + 1 < len(a) else None


def die(msg):
    open(os.path.join(S, "obs-error"), "w").write(msg + "\n")
    sys.stderr.write(msg + "\n")
    sys.exit(3)


profile, coll, scene = arg("--profile"), arg("--collection"), arg("--scene")
ini = os.path.join(CFG, "basic/profiles/Ultimit_Broadcast/basic.ini")
if not os.path.exists(ini) or "Name=%s" % profile not in open(ini).read():
    die("profile %r not found" % profile)
sc = json.load(open(os.path.join(CFG, "basic/scenes/Ultimit_Broadcast.json")))
if sc["name"] != coll or sc["current_scene"] != scene:
    die("scene collection / scene not found")
ws_cfg = json.load(open(os.path.join(CFG, "plugin_config/obs-websocket/config.json")))
if not ws_cfg.get("server_enabled") or ws_cfg.get("server_port") != PORT:
    die("websocket server not enabled on %d" % PORT)
PASSWORD = ws_cfg["server_password"]

sources = {s["name"]: {"kind": s["id"], "settings": dict(s["settings"]),
                       "filters": {f["name"]: {"id": f["id"], "enabled": f["enabled"], "settings": dict(f["settings"])}
                                   for f in s.get("filters", [])}} for s in sc["sources"]}
items = {i["id"]: {"name": i["name"], "enabled": i["visible"]} for i in sc["sources"][0]["settings"]["items"]}
state = {"profile": profile, "collection": coll, "scene": scene, "sources": sources, "items": items,
         "vcam": "--startvirtualcam" in sys.argv, "flags": sys.argv[1:], "log": []}


def save():
    json.dump(state, open(os.path.join(S, "obs-state.json"), "w"), indent=1)


def reply(ok, code=100, comment="", data=None):
    st = {"result": ok, "code": code}
    if comment: st["comment"] = comment
    return st, data


def handle(t, d):
    state["log"].append(t)
    if t == "GetVersion": return reply(True, data={"obsVersion": "32.2.2-fake", "obsWebSocketVersion": "5.5.0", "rpcVersion": 1})
    if t == "GetVirtualCamStatus": return reply(True, data={"outputActive": state["vcam"]})
    if t == "StartVirtualCam":
        if state["vcam"]: return reply(False, 500, "Virtual camera is already running.")
        state["vcam"] = True; return reply(True)
    if t == "StopVirtualCam":
        if not state["vcam"]: return reply(False, 501, "Virtual camera is not running.")
        state["vcam"] = False; return reply(True)
    if t == "SetInputSettings":
        s = sources.get(d.get("inputName"))
        if not s: return reply(False, 600, "No input")
        if d.get("overlay") is False: s["settings"] = {}
        s["settings"].update(d["inputSettings"]); return reply(True)
    if t in ("SetSourceFilterSettings", "SetSourceFilterEnabled"):
        f = sources.get(d.get("sourceName"), {}).get("filters", {}).get(d.get("filterName"))
        if not f: return reply(False, 600, "No filter")
        if t == "SetSourceFilterEnabled": f["enabled"] = d["filterEnabled"]
        else: f["settings"].update(d["filterSettings"])
        return reply(True)
    if t == "SetSceneItemEnabled":
        i = items.get(d.get("sceneItemId"))
        if not i or d.get("sceneName") != scene: return reply(False, 600, "No scene item")
        i["enabled"] = d["sceneItemEnabled"]; return reply(True)
    if t == "GetSourceScreenshot":
        if d.get("sourceName") != scene: return reply(False, 600, "No source")
        img = open(os.path.join(HERE, "preview.jpg"), "rb").read()
        return reply(True, data={"imageData": "data:image/jpeg;base64," + base64.b64encode(img).decode()})
    return reply(False, 204, "Unknown request type")


async def conn(ws):
    salt, chal = secrets.token_urlsafe(16), secrets.token_urlsafe(16)
    await ws.send(json.dumps({"op": 0, "d": {"obsWebSocketVersion": "5.5.0", "rpcVersion": 1, "authentication": {"challenge": chal, "salt": salt}}}))
    ident = json.loads(await ws.recv())
    sec = base64.b64encode(hashlib.sha256((PASSWORD + salt).encode()).digest()).decode()
    want = base64.b64encode(hashlib.sha256((sec + chal).encode()).digest()).decode()
    if ident.get("op") != 1 or ident["d"].get("authentication") != want:
        await ws.close(4009, "Authentication failed.")
        return
    await ws.send(json.dumps({"op": 2, "d": {"negotiatedRpcVersion": 1}}))
    async for raw in ws:
        m = json.loads(raw)
        if m.get("op") != 6: continue
        d = m["d"]
        st, data = handle(d["requestType"], d.get("requestData") or {})
        save()
        r = {"requestType": d["requestType"], "requestId": d["requestId"], "requestStatus": st}
        if data is not None: r["responseData"] = data
        await ws.send(json.dumps({"op": 7, "d": r}))


async def main():
    from websockets.asyncio.server import serve
    stop = asyncio.get_running_loop().create_future()
    asyncio.get_running_loop().add_signal_handler(signal.SIGTERM, lambda: stop.done() or stop.set_result(1))
    async with serve(conn, "127.0.0.1", PORT):
        save()
        await stop
    state["exited"] = "clean"
    save()
    try: os.remove(os.path.join(S, "obs.pid"))
    except OSError: pass

asyncio.run(main())
