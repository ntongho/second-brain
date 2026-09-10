from app.services.chunker import TEXT_SIZE, chunk_text


def test_offset_invariant_and_size():
    t = ("Paragraph one. " * 40) + "\n\n" + ("Paragraph two. " * 40)
    chunks = chunk_text(t)
    assert chunks
    for c in chunks:
        assert c.end_char - c.start_char == len(c.text)
        assert len(c.text) <= TEXT_SIZE
        assert t[c.start_char : c.end_char] == c.text


def test_short_text_single_chunk():
    t = "hello world"
    chunks = chunk_text(t)
    assert len(chunks) == 1
    assert chunks[0].start_char == 0 and chunks[0].end_char == len(t)


def test_empty():
    assert chunk_text("") == []


def test_code_smaller_window():
    t = "x" * 2000
    code = chunk_text(t, is_code=True)
    text = chunk_text(t, is_code=False)
    assert all(len(c.text) <= 600 for c in code)
    assert all(len(c.text) <= 800 for c in text)


def test_50k_line_no_separators():
    t = "a" * 50_000
    chunks = chunk_text(t)
    assert chunks
    assert sum(len(c.text) for c in chunks) >= 50_000 - 100 * (len(chunks) - 1)
    for c in chunks:
        assert c.end_char - c.start_char == len(c.text) <= 800
