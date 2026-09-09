"""Local-only OBS protocol fixture. Never controls a real OBS process."""
import base64
import hashlib
import json
from pathlib import Path
import socket
import struct
import sys
import threading
import time

mode, ready_path = sys.argv[1:]
barrier = threading.Barrier(2)
counter_lock = threading.Lock()
counter = 0


def exact(conn, count):
    data = b""
    while len(data) < count:
        part = conn.recv(count - len(data))
        if not part:
            raise EOFError()
        data += part
    return data


def receive(conn):
    header = exact(conn, 2)
    opcode, length = header[0] & 15, header[1] & 127
    if opcode == 8:
        raise EOFError()
    if length == 126:
        length = struct.unpack("!H", exact(conn, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", exact(conn, 8))[0]
    mask = exact(conn, 4) if header[1] & 128 else None
    body = exact(conn, length)
    if mask:
        body = bytes(value ^ mask[index % 4] for index, value in enumerate(body))
    return json.loads(body)


def send(conn, payload):
    body = json.dumps(payload).encode()
    length = len(body)
    header = bytes([0x81, length]) if length < 126 else b"\x81\x7e" + struct.pack("!H", length)
    conn.sendall(header + body)


def handle(conn):
    global counter
    try:
        conn.settimeout(4)
        header = b""
        while not header.endswith(b"\r\n\r\n"):
            header += exact(conn, 1)
        headers = dict(line.split(":", 1) for line in header.decode().split("\r\n")[1:] if ":" in line)
        key = next(value.strip() for name, value in headers.items() if name.lower() == "sec-websocket-key")
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        send(conn, {"op": 0, "d": {"rpcVersion": 1}})
        identify = receive(conn)
        assert identify["op"] == 1 and identify["d"]["eventSubscriptions"] == 0
        send(conn, {"op": 2, "d": {"negotiatedRpcVersion": 1}})
        request = receive(conn)["d"]
        kind = request["requestType"]
        assert kind in ("GetStreamStatus", "StopStream", "GetRecordStatus")
        Path(ready_path).write_text(kind)
        if mode == "stall" or (mode == "stop_status_stall" and kind == "GetStreamStatus"):
            time.sleep(3)
            return
        with counter_lock:
            counter += 1
            index = counter
        if mode == "concurrent":
            barrier.wait(timeout=3)
        code = 501 if kind == "StopStream" and mode.startswith("already_") else 100
        if kind == "GetRecordStatus":
            data = {"outputActive": True}
        elif kind == "GetStreamStatus":
            data = {"outputActive": mode == "concurrent" and index == 1,
                    "outputReconnecting": mode in ("stopping", "already_reconnecting")}
            if mode == "stop_later":
                data["outputActive"] = index == 2
            if mode == "malformed":
                data = {}
        else:
            data = {}
        send(conn, {"op": 7, "d": {"requestId": request["requestId"], "requestType": kind,
                    "requestStatus": {"result": code == 100, "code": code, "comment": "fixture"}, "responseData": data}})
        # Wait for the client to close so the test covers a completed frame,
        # rather than an incidental abrupt transport disconnection.
        try:
            receive(conn)
        except (EOFError, OSError):
            pass
    except (EOFError, OSError, ValueError, threading.BrokenBarrierError):
        pass
    finally:
        conn.close()


listener = socket.socket()
listener.bind(("127.0.0.1", 0))
listener.listen(16)
print(listener.getsockname()[1], flush=True)
while True:
    connection, _ = listener.accept()
    threading.Thread(target=handle, args=(connection,), daemon=True).start()
