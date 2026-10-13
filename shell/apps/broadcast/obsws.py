"""obsws.py - a tiny obs-websocket v5 client for BROADCAST (stdlib + the `websockets` module).

One short session per call: connect, authenticate, send requests one after another, close. The transport
(`transport(port, password, requests, timeout)`) is a module-level function so tests can replace it.

  request(type, **data)    -> {"type":..., "data":{...}}     (pure, what the tests inspect)
  auth_string(password, salt, challenge)                     (obs-websocket 5 authentication)
  call(requests, port, password, timeout=8)  -> [result...]  result = {ok, code, comment, data}
"""
import asyncio
import base64
import hashlib
import json
import uuid


class ObsError(Exception):
    pass


def request(rtype, **data):
    return {"type": rtype, "data": data}


def auth_string(password, salt, challenge):
    secret = base64.b64encode(hashlib.sha256((password + salt).encode()).digest()).decode()
    return base64.b64encode(hashlib.sha256((secret + challenge).encode()).digest()).decode()


def encode_request(req, request_id):
    d = {"requestType": req["type"], "requestId": request_id}
    if req.get("data"):
        d["requestData"] = req["data"]
    return json.dumps({"op": 6, "d": d})


def identify_message(hello, password):
    d = {"rpcVersion": 1}
    a = hello.get("authentication")
    if a:
        if not password:
            raise ObsError("OBS asks for a password")
        d["authentication"] = auth_string(password, a["salt"], a["challenge"])
    return json.dumps({"op": 1, "d": d})


def parse_result(msg):
    st = msg.get("requestStatus", {})
    return {"ok": bool(st.get("result")), "code": st.get("code", 0), "comment": st.get("comment", ""),
            "data": msg.get("responseData") or {}}


async def _session(port, password, requests, timeout):
    from websockets.asyncio.client import connect
    url = "ws://127.0.0.1:%d" % port
    async with connect(url, open_timeout=timeout, close_timeout=2, max_size=16 * 1024 * 1024) as ws:
        hello = json.loads(await asyncio.wait_for(ws.recv(), timeout))
        if hello.get("op") != 0:
            raise ObsError("unexpected greeting from OBS")
        await ws.send(identify_message(hello["d"], password))
        ident = json.loads(await asyncio.wait_for(ws.recv(), timeout))
        if ident.get("op") != 2:
            raise ObsError("OBS refused the login")
        results = []
        for req in requests:
            rid = uuid.uuid4().hex
            await ws.send(encode_request(req, rid))
            while True:
                msg = json.loads(await asyncio.wait_for(ws.recv(), timeout))
                if msg.get("op") == 7 and msg["d"].get("requestId") == rid:
                    results.append(parse_result(msg["d"]))
                    break
        return results


def default_transport(port, password, requests, timeout=8):
    try:
        return asyncio.run(_session(port, password, requests, timeout))
    except ObsError:
        raise
    except Exception as e:  # refused, timed out, closed, bad frame...
        raise ObsError("%s: %s" % (type(e).__name__, e) if str(e) else type(e).__name__)


transport = default_transport


def call(requests, port, password, timeout=8):
    return transport(port, password, requests, timeout)
