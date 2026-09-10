from __future__ import annotations

import struct
from pathlib import Path

from app.core.config import get_settings
from app.core.errors import AppError

MAX_BYTES = 25 * 1024 * 1024
MAX_SECONDS = 10 * 60
AUDIO_EXTS = ("wav", "webm", "mp3", "m4a", "ogg", "mp4")


def sniff_media(blob: bytes) -> str:
    """Return 'pdf' | 'voice' | 'unknown' from magic bytes."""
    head = blob[:16]
    if blob.lstrip()[:4] == b"%PDF":
        return "pdf"
    if head[:4] == b"RIFF" and blob[8:12] == b"WAVE":
        return "voice"
    if head[:4] == b"OggS":
        return "voice"
    if head[:4] == b"fLaC":
        return "voice"
    if head[:3] == b"ID3" or (len(head) >= 2 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0):
        return "voice"
    if head[:4] == b"\x1aE\xdf\xa3":  # EBML / webm
        return "voice"
    if b"ftyp" in blob[:32]:
        return "voice"
    return "unknown"


def ext_for_blob(blob: bytes) -> str:
    head = blob[:16]
    if head[:4] == b"RIFF" and blob[8:12] == b"WAVE":
        return "wav"
    if head[:4] == b"OggS":
        return "ogg"
    if head[:4] == b"\x1aE\xdf\xa3":
        return "webm"
    if b"ftyp" in blob[:32]:
        return "m4a"
    if head[:3] == b"ID3" or (len(head) >= 2 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0):
        return "mp3"
    return "bin"


def wav_duration_seconds(blob: bytes) -> float | None:
    if len(blob) < 44 or blob[:4] != b"RIFF" or blob[8:12] != b"WAVE":
        return None
    offset = 12
    channels = sample_rate = bits = None
    data_size = None
    while offset + 8 <= len(blob):
        chunk_id = blob[offset : offset + 4]
        chunk_size = struct.unpack_from("<I", blob, offset + 4)[0]
        start = offset + 8
        if chunk_id == b"fmt " and chunk_size >= 16:
            channels = struct.unpack_from("<H", blob, start + 2)[0]
            sample_rate = struct.unpack_from("<I", blob, start + 4)[0]
            bits = struct.unpack_from("<H", blob, start + 14)[0]
        elif chunk_id == b"data":
            data_size = chunk_size
            break
        offset = start + chunk_size + (chunk_size & 1)
    if not channels or not sample_rate or not bits or data_size is None:
        return None
    bytes_per_sec = sample_rate * channels * max(bits, 1) / 8
    if bytes_per_sec <= 0:
        return None
    return data_size / bytes_per_sec


def assert_audio(blob: bytes, *, duration_hint: float | None = None) -> float:
    if len(blob) > MAX_BYTES:
        raise AppError(
            413,
            "VALIDATION",
            "File too large (max 25MB)",
            details={"max_bytes": MAX_BYTES},
        )
    if sniff_media(blob) != "voice":
        raise AppError(422, "VALIDATION", "Not an audio file", details={"reason": "magic"})
    duration = wav_duration_seconds(blob)
    if duration is None:
        duration = duration_hint
    if duration is None:
        # ~16 kHz 16-bit mono lower bound; overestimate so we don't skip the cap.
        duration = len(blob) / 4000.0
    if duration > MAX_SECONDS + 0.05:
        raise AppError(
            413,
            "VALIDATION",
            "Audio longer than 10 minutes",
            details={"max_seconds": MAX_SECONDS, "duration_seconds": round(duration, 2)},
        )
    return float(duration)


def media_path(doc_id: str, ext: str) -> Path:
    return Path(get_settings().files_path) / f"{doc_id}.{ext}"


def save_media_bytes(doc_id: str, blob: bytes, ext: str) -> Path:
    path = media_path(doc_id, ext)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)
    return path


def load_media_bytes(doc_id: str) -> tuple[bytes, str] | None:
    base = Path(get_settings().files_path)
    for ext in ("pdf", *AUDIO_EXTS, "bin"):
        path = base / f"{doc_id}.{ext}"
        if path.exists():
            return path.read_bytes(), ext
    return None


def delete_media_bytes(doc_id: str) -> None:
    base = Path(get_settings().files_path)
    for ext in ("pdf", *AUDIO_EXTS, "bin"):
        path = base / f"{doc_id}.{ext}"
        if path.exists():
            path.unlink()
