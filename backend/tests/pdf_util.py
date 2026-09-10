from __future__ import annotations


def make_pdf(pages: list[str]) -> bytes:
    """Minimal multi-page PDF with one text line per page."""
    n = len(pages)
    kids = " ".join(f"{3 + i} 0 R" for i in range(n))
    objects: list[bytes] = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        f"<< /Type /Pages /Kids [{kids}] /Count {n} >>".encode(),
    ]
    # page objects 3..3+n-1, contents 3+n .., font last
    content_ids = [3 + n + i for i in range(n)]
    font_id = 3 + 2 * n
    for i, _ in enumerate(pages):
        pid = 3 + i
        cid = content_ids[i]
        objects.append(
            (
                f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                f"/Contents {cid} 0 R /Resources << /Font << /F1 {font_id} 0 R >> >> >>"
            ).encode()
        )
    for text in pages:
        safe = "".join(ch if 32 <= ord(ch) < 127 and ch not in "()\\" else " " for ch in text)
        stream = f"BT /F1 12 Tf 50 700 Td ({safe}) Tj ET\n".encode()
        objects.append(b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"endstream")
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for i, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects)+1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)
