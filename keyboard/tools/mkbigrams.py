#!/usr/bin/env python3
"""Builds a language's bigrams.tsv: mkbigrams.py words.tsv OUT sentences.tsv.bz2 (Tatoeba sentences).
Each line: the folded previous word, tab, up to 10 next words. "<s>" starts a sentence, "<*>" holds the commonest words."""
import bz2, collections, re, sys, unicodedata
wordsf, out, *srcs = sys.argv[1:]
MIN_COUNT, HEADS, TOP = 3, 4000, 10
# the sentence collection's stock characters
BLOCK = {"tom", "mary", "john", "sami", "layla"}
TOKEN = re.compile(r"[^\W\d_]+(?:['’-][^\W\d_]+)*")

def fold(w):
    w = w.lower().replace("'", "").replace("-", "")
    return "".join(c for c in unicodedata.normalize("NFD", w) if not unicodedata.combining(c))

def norm(w):
    return w.lower().replace("ş", "ș").replace("ţ", "ț").replace("’", "'")

known = set()
for line in open(wordsf, encoding="utf-8"):
    k, w, *_ = line.rstrip("\n").split("\t")
    known.add(w or k)
per_lang = []
for src in srcs:
    pairs = collections.defaultdict(collections.Counter)
    common = collections.Counter()
    for line in bz2.open(src, "rt", encoding="utf-8", errors="replace"):
        text = line.rstrip("\n").split("\t")[-1]
        for sentence in re.split(r"[.!?…]+", text):
            prev = "<s>"
            for i, m in enumerate(TOKEN.finditer(sentence)):
                raw, w = m[0], norm(m[0])
                w = "I" if w == "i" and "eng" in src else w
                # a capital inside a sentence is a name, and names are not predictions
                if w not in known or w in BLOCK or (i and raw[0].isupper() and w != "I"):
                    prev = None
                    continue
                if prev:
                    pairs[prev][w] += 1
                prev = fold(w)
                common[w] += 1
    keep = sorted(pairs, key=lambda h: -sum(pairs[h].values()))[:HEADS]
    per_lang.append({h: [w for w, c in pairs[h].most_common(TOP) if c >= MIN_COUNT] for h in keep})
    per_lang[-1]["<*>"] = [w for w, c in common.most_common(6)]
heads = sorted({h for p in per_lang for h in p}, key=lambda s: s.encode())
with open(out, "w", encoding="utf-8", newline="\n") as f:
    for h in heads:
        top = list(dict.fromkeys(w for p in per_lang for w in p.get(h, [])))
        if top:
            f.write(f"{h}\t{' '.join(top)}\n")
