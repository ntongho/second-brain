"""Generate + validate Second Brain fixtures (v1.1). Run: python fixtures/generate_fixtures.py"""
import json
import pathlib

ROOT = pathlib.Path(__file__).parent


def load(n):
    return json.loads((ROOT / n).read_text(encoding="utf-8"))


def main():
    docs = load("docs-seed.json")
    assert len(docs) == 12, "need D1..D12, got %d" % len(docs)
    ids = {d["local_id"] for d in docs}
    assert {"D10", "D11", "D12"} <= ids, "distractor/second-invoice/follow-up docs missing"
    assert any(d["local_id"] == "D6" and "INV-9082" in d["text"] for d in docs), "hybrid trap doc missing"
    assert any("no tax advice" in d["text"] for d in docs if d["local_id"] == "D10"), "D10 must disclaim tax content"
    t = docs[0]["text"]
    chunks = []
    i = 0
    while i < len(t):
        j = min(i + 800, len(t))
        chunks.append((i, j))
        if j == len(t):
            break
        i = j - 100
    for s, e in chunks:
        assert e - s <= 800 and s < e
    print(f"OK: {len(docs)} docs (qa-golden / adversarial land in later phases).")
    print("Next: python fixtures/seed_api.py, then python fixtures/run_eval.py --suite smoke")


if __name__ == "__main__":
    main()
