#!/usr/bin/env python3
"""Builds data/words.tsv: mkwords.py SRC OUT. SRC holds ro_50k.txt, en_50k.txt (FrequencyWords)
and the ro_RO, en_US hunspell dictionaries, which only decide which words are kept."""
import math, re, subprocess, sys, unicodedata
src, out = sys.argv[1:3]
RO, EN = 30000, 25000
BLOCK = set("""fuck fucking fucked fucker fuckin motherfucker shit shitty bullshit cunt bitch bitches
asshole dick cock pussy whore slut nigger faggot pula pulă pizda pizdă muie cacat căcat futu fututi
futut târfă tarfa curvă curva""".split())
ALWAYS = {"a", "i", "o", "e", "y", "u"}
EN_FIX = {"i": "I"}
CONTRACTIONS = """don't can't won't I'm it's that's you're we're they're I've isn't aren't wasn't
weren't didn't doesn't couldn't wouldn't shouldn't I'll you'll he's she's what's let's there's I'd
you've we've we'll haven't hasn't""".split()

def fold(w):
    w = w.lower().replace("'", "").replace("-", "")
    return "".join(c for c in unicodedata.normalize("NFD", w) if not unicodedata.combining(c))

def norm(w):
    return w.replace("ş", "ș").replace("ţ", "ț").replace("Ş", "Ș").replace("Ţ", "Ț")

def load(name):
    d = {}
    for line in open(f"{src}/{name}", encoding="utf-8"):
        w, n = line.split()
        d[norm(w)] = d.get(norm(w), 0) + int(n)
    return d

def bad(words, dic):
    r = subprocess.run(["hunspell", "-d", f"{src}/{dic}", "-l"], input="\n".join(words), capture_output=True, text=True)
    return set(r.stdout.split())

def build(name, dic, letters, keep, lang):
    raw = load(name)
    total = sum(raw.values())
    words = [w for w in raw if re.fullmatch(letters, w) and w not in BLOCK and fold(w) not in BLOCK
             and (len(w) > 1 or w in ALWAYS)]
    wrong = bad(words, dic)
    good = {w: raw[w] for w in words if w not in wrong}
    # a misspelled form without diacritics counts for the word it stands for
    best = {}
    for w, n in good.items():
        if fold(w) not in best or n > good[best[fold(w)]]:
            best[fold(w)] = w
    for w in words:
        if w in wrong and fold(w) in best:
            good[best[fold(w)]] += raw[w]
    top = sorted(good, key=good.get, reverse=True)[:keep]
    return {w: (round(16 * math.log2(good[w] / total * 1e9 + 1)), lang) for w in top}

ro = build("ro_50k.txt", "ro_RO", r"[a-zăâîșț]+(-[a-zăâîșț]+)*", RO, "r")
en = build("en_50k.txt", "en_US", r"[a-z]+", EN, "e")
en.pop("don", None)
for w, fix in EN_FIX.items():
    if w in en:
        en[fix] = en.pop(w)
for w in CONTRACTIONS:
    en[w] = (300, "e")
rows = {}
for table in (ro, en):
    for w, (score, lang) in table.items():
        if w in rows:
            rows[w] = (max(score, rows[w][0]), "b")
        else:
            rows[w] = (score, lang)
lines = sorted((fold(w).encode(), -s, w, l) for w, (s, l) in rows.items())
with open(out, "w", encoding="utf-8", newline="\n") as f:
    for key, s, w, l in lines:
        k = key.decode()
        f.write(f"{k}\t{'' if w == k else w}\t{-s}\t{l}\n")
print(len(lines), "words")
