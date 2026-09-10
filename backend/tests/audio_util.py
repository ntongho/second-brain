from __future__ import annotations

import struct


def make_wav(*, seconds: float, sample_rate: int = 8000) -> bytes:
    n = max(1, int(seconds * sample_rate))
    data = b"\x00\x00" * n
    byte_rate = sample_rate * 2
    return _wav(data, sample_rate=sample_rate, byte_rate=byte_rate, data_size=len(data))


def make_wav_claiming_duration(seconds: float, sample_rate: int = 8000) -> bytes:
    """Tiny WAV whose header claims `seconds` (AUD-01 without a 12MB payload)."""
    data = b"\x00\x00" * 64
    claimed = int(seconds * sample_rate * 2)
    byte_rate = sample_rate * 2
    return _wav(data, sample_rate=sample_rate, byte_rate=byte_rate, data_size=claimed)


def _wav(data: bytes, *, sample_rate: int, byte_rate: int, data_size: int) -> bytes:
    fmt = struct.pack("<HHIIHH", 1, 1, sample_rate, byte_rate, 2, 16)
    riff_size = 4 + (8 + 16) + (8 + data_size)
    out = bytearray()
    out += b"RIFF" + struct.pack("<I", riff_size) + b"WAVE"
    out += b"fmt " + struct.pack("<I", 16) + fmt
    out += b"data" + struct.pack("<I", data_size) + data
    return bytes(out)
