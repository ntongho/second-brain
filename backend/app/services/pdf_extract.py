from __future__ import annotations

from dataclasses import dataclass

from app.core.errors import AppError

PDF_MAGIC = b"%PDF"
MAX_BYTES = 25 * 1024 * 1024
MAX_PAGES = 500
PAGE_SEP = "\f"


@dataclass
class ExtractedPdf:
    text: str
    page_count: int


def page_for_char(raw: str, start_char: int, source_type: str) -> int | None:
    if source_type != "pdf" or not raw:
        return None
    s = max(0, min(start_char, len(raw)))
    return raw[:s].count(PAGE_SEP) + 1


def assert_pdf_magic_and_size(blob: bytes) -> None:
    if len(blob) > MAX_BYTES:
        raise AppError(413, "VALIDATION", "File too large (max 25MB)")
    if not blob.lstrip().startswith(PDF_MAGIC):
        raise AppError(422, "VALIDATION", "Not a PDF (magic bytes)", details={"reason": "magic"})


def extract_pdf(blob: bytes) -> ExtractedPdf:
    assert_pdf_magic_and_size(blob)
    pages: list[str] = []
    try:
        import pypdfium2 as pdfium

        doc = pdfium.PdfDocument(blob)
        try:
            if len(doc) > MAX_PAGES:
                raise AppError(413, "VALIDATION", "PDF exceeds 500 pages")
            for page in doc:
                textpage = page.get_textpage()
                try:
                    pages.append((textpage.get_text_bounded() or "").replace("\x00", ""))
                finally:
                    textpage.close()
                    page.close()
        finally:
            doc.close()
    except AppError:
        raise
    except Exception:
        from io import BytesIO

        from pypdf import PdfReader

        reader = PdfReader(BytesIO(blob))
        if len(reader.pages) > MAX_PAGES:
            raise AppError(413, "VALIDATION", "PDF exceeds 500 pages")
        for page in reader.pages:
            pages.append((page.extract_text() or "").replace("\x00", ""))
    if len(pages) > MAX_PAGES:
        raise AppError(413, "VALIDATION", "PDF exceeds 500 pages")
    text = PAGE_SEP.join(pages)
    if not text.strip():
        raise AppError(422, "VALIDATION", "PDF has no extractable text", details={"reason": "empty"})
    return ExtractedPdf(text=text, page_count=len(pages))


def split_pages(raw: str) -> list[str]:
    return raw.split(PAGE_SEP)


def pdf_path(doc_id: str):
    from pathlib import Path

    from app.core.config import get_settings

    return Path(get_settings().files_path) / f"{doc_id}.pdf"


def save_pdf_bytes(doc_id: str, blob: bytes) -> None:
    path = pdf_path(doc_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(blob)


def delete_pdf_bytes(doc_id: str) -> None:
    path = pdf_path(doc_id)
    if path.exists():
        path.unlink()


def render_page_png(blob: bytes, page_index: int, *, scale: float = 1.7) -> bytes | None:
    """page_index is 1-based. Returns PNG bytes or None."""
    try:
        from io import BytesIO

        import pypdfium2 as pdfium

        doc = pdfium.PdfDocument(blob)
        try:
            if page_index < 1 or page_index > len(doc):
                return None
            page = doc[page_index - 1]
            bitmap = page.render(scale=scale)
            try:
                pil = bitmap.to_pil()
                buf = BytesIO()
                pil.save(buf, format="PNG")
                return buf.getvalue()
            finally:
                page.close()
        finally:
            doc.close()
    except Exception:
        return None
