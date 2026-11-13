#!/usr/bin/env python3
"""Splits the output of mkwords.py and mkbigrams.py into the English base and the Romanian pack:
splitlang.py MERGED_WORDS MERGED_BIGRAMS DATA_DIR PACKS_DIR. phonekbd-lang merge is its inverse."""
import hashlib, os, sys
words, bigrams, data, packs = sys.argv[1:5]
tag = {}
base, ro = [], []
for line in open(words, encoding="utf-8"):
    k, w, s, l = line.rstrip("\n").split("\t")
    tag[w or k] = l
    if l in "eb":
        base.append(f"{k}\t{w}\t{s}\te\n")
    if l in "rb":
        ro.append(f"{k}\t{w}\t{s}\tr\n")
biben, biro = [], []
for line in open(bigrams, encoding="utf-8"):
    h, nexts = line.rstrip("\n").split("\t")
    en = [w for w in nexts.split() if tag.get(w) in ("e", "b")]
    rr = [w for w in nexts.split() if tag.get(w) in ("r", "b")]
    if en:
        biben.append(f"{h}\t{' '.join(en)}\n")
    if rr:
        biro.append(f"{h}\t{' '.join(rr)}\n")
os.makedirs(f"{packs}/ro", exist_ok=True)
def write(path, lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(lines)
write(f"{data}/words.tsv", base)
write(f"{data}/bigrams.tsv", biben)
write(f"{packs}/ro/words.tsv", ro)
write(f"{packs}/ro/bigrams.tsv", biro)
write(f"{packs}/ro/letters", ["a\tă\tĂ\n", "a\tâ\tÂ\n", "i\tî\tÎ\n", "s\tș\tȘ\n", "t\tț\tȚ\n"])
with open(f"{packs}/index.tsv", "w", newline="\n") as idx:
    for lang in sorted(d for d in os.listdir(packs) if os.path.isdir(f"{packs}/{d}")):
        for name in ("words.tsv", "bigrams.tsv", "letters"):
            b = open(f"{packs}/{lang}/{name}", "rb").read()
            idx.write(f"{lang}\t{name}\t{len(b)}\t{hashlib.sha256(b).hexdigest()}\n")
print(len(base), "base words,", len(ro), "ro words,", len(biben), "base heads,", len(biro), "ro heads")
