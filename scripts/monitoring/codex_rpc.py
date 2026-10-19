"""Small local app-server client using the installed Codex proxy and WebSocket transport."""

import base64
import hashlib
import json
import os
from pathlib import Path
import queue
import struct
import subprocess
import threading
import time


class CodexRpc:
    def __init__(self, executable, timeout=20):
        self.timeout = timeout
        self.sequence = 0
        self.buffer = bytearray()
        self.chunks = queue.Queue()
        self.process = subprocess.Popen(
            [str(executable), "app-server", "proxy"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        try:
            key = base64.b64encode(os.urandom(16)).decode("ascii")
            self._write((
                "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
                "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                f"Sec-WebSocket-Key: {key}\r\n\r\n"
            ).encode("ascii"))
            header = bytearray()
            deadline = time.monotonic() + timeout
            while not header.endswith(b"\r\n\r\n"):
                header.extend(self._read_exact(1, deadline))
                if len(header) > 16384:
                    raise RuntimeError("Oversized WebSocket handshake")
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()).decode("ascii")
            header_text = header.decode("ascii").lower()
            if "101 switching protocols" not in header_text or expected.lower() not in header_text:
                raise RuntimeError("Local Codex WebSocket handshake failed")
            self.call("initialize", {
                "clientInfo": {"name": "omnivibe_skin_monitor", "version": "1.0"},
                "capabilities": {"experimentalApi": True},
            })
            self.notify("initialized", {})
        except Exception:
            self.close()
            raise

    def _read_stdout(self):
        try:
            while True:
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    break
                self.chunks.put(chunk)
        finally:
            self.chunks.put(None)

    def _read_exact(self, size, deadline):
        while len(self.buffer) < size:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Local Codex response timed out")
            try:
                chunk = self.chunks.get(timeout=remaining)
            except queue.Empty as exc:
                raise TimeoutError("Local Codex response timed out") from exc
            if chunk is None:
                raise ConnectionError("Local Codex proxy closed")
            self.buffer.extend(chunk)
        result = bytes(self.buffer[:size])
        del self.buffer[:size]
        return result

    def _write(self, data):
        self.process.stdin.write(data)
        self.process.stdin.flush()

    def _send_frame(self, payload, opcode=1):
        size = len(payload)
        if size < 126:
            header = bytes([0x80 | opcode, 0x80 | size])
        elif size < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack("!H", size)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack("!Q", size)
        mask = os.urandom(4)
        self._write(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def _read_message(self, deadline):
        fragments = bytearray()
        while True:
            first, second = self._read_exact(2, deadline)
            size = second & 127
            if size == 126:
                size = struct.unpack("!H", self._read_exact(2, deadline))[0]
            elif size == 127:
                size = struct.unpack("!Q", self._read_exact(8, deadline))[0]
            if size > 32 * 1024 * 1024:
                raise RuntimeError("Oversized local Codex response")
            mask = self._read_exact(4, deadline) if second & 128 else None
            payload = self._read_exact(size, deadline)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            opcode = first & 15
            if opcode == 8:
                raise ConnectionError("Local Codex closed WebSocket")
            if opcode == 9:
                self._send_frame(payload, 10)
                continue
            if opcode == 10:
                continue
            if opcode not in (0, 1):
                raise RuntimeError("Unexpected local Codex frame")
            fragments.extend(payload)
            if first & 128:
                return json.loads(fragments.decode("utf-8"))

    def notify(self, method, params):
        self._send_frame(json.dumps({"method": method, "params": params}).encode("utf-8"))

    def call(self, method, params):
        self.sequence += 1
        identifier = self.sequence
        self._send_frame(json.dumps({"id": identifier, "method": method, "params": params}).encode("utf-8"))
        deadline = time.monotonic() + self.timeout
        while True:
            message = self._read_message(deadline)
            if message.get("id") != identifier:
                continue
            if "error" in message:
                raise RuntimeError(f"{method}: {message['error']}")
            return message.get("result", {})

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            stream.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
