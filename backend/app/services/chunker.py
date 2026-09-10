from __future__ import annotations

from dataclasses import dataclass

SEPARATORS = ["\n\n", "\n", ". ", " ", ""]
TEXT_SIZE, TEXT_OVERLAP = 800, 100
CODE_SIZE, CODE_OVERLAP = 600, 80


@dataclass(frozen=True)
class ChunkSpan:
    text: str
    start_char: int
    end_char: int
    ord: int

    def __post_init__(self) -> None:
        if self.end_char - self.start_char != len(self.text):
            raise AssertionError("offset invariant: end-start == len(text)")


def chunk_text(
    text: str,
    *,
    is_code: bool = False,
) -> list[ChunkSpan]:
    """Recursive splitter. Locked: 800/100 (code 600/80), seps [\\n\\n, \\n, '. ', ' ', '']."""
    if not text:
        return []
    size = CODE_SIZE if is_code else TEXT_SIZE
    overlap = CODE_OVERLAP if is_code else TEXT_OVERLAP
    raw = _window_split(text, size, overlap, SEPARATORS)
    out: list[ChunkSpan] = []
    for i, (s, e, piece) in enumerate(raw):
        if not piece:
            continue
        span = ChunkSpan(text=piece, start_char=s, end_char=e, ord=i)
        if e - s > size:
            raise AssertionError(f"chunk longer than {size}: {e - s}")
        out.append(span)
    return out


def _window_split(text: str, size: int, overlap: int, seps: list[str]) -> list[tuple[int, int, str]]:
    n = len(text)
    if n <= size:
        return [(0, n, text)]
    chunks: list[tuple[int, int, str]] = []
    start = 0
    while start < n:
        end = min(start + size, n)
        if end < n:
            window = text[start:end]
            cut: int | None = None
            for sep in seps:
                if not sep:
                    continue
                i = window.rfind(sep)
                # Don't collapse to a tiny first fragment.
                if i >= max(1, size // 5):
                    cut = start + i + len(sep)
                    break
            if cut is None:
                cut = end
            end = cut
        if end <= start:
            end = min(start + size, n)
        piece = text[start:end]
        chunks.append((start, end, piece))
        if end >= n:
            break
        nxt = end - overlap
        start = nxt if nxt > start else start + 1
    return chunks
