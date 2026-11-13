#!/usr/bin/env python3
"""Builds data/emoji.tsv: mkemoji.py emoji-test.txt en.xml ro.xml OUT.
Each line: group, sequence, light skin tone template or empty, folded search words.
A template holds U+1F3FB wherever a tone goes, so two person sequences stay right."""
import re, sys, unicodedata
import xml.etree.ElementTree as ET
test, en, ro, out = sys.argv[1:5]
GROUPS = ["Smileys & Emotion", "People & Body", "Animals & Nature", "Food & Drink", "Travel & Places",
          "Activities", "Objects", "Symbols", "Flags"]
TONES = "\U0001F3FB\U0001F3FC\U0001F3FD\U0001F3FE\U0001F3FF"

def fold(s):
    s = "".join(c for c in unicodedata.normalize("NFD", s.lower()) if not unicodedata.combining(c))
    return re.findall(r"[a-z0-9]+", s)

def annotations(path):
    res = {}
    for a in ET.parse(path).getroot().iter("annotation"):
        if a.text and a.text != "↑↑↑":
            res.setdefault(a.get("cp").replace("️", ""), []).extend(a.text.replace("|", " ").split())
    return res

ann = [annotations(en), annotations(ro)]
entries, tone_of, group = [], {}, None
for line in open(test, encoding="utf-8"):
    m = re.match(r"# group: (.*)", line)
    if m:
        group = GROUPS.index(m[1]) if m[1] in GROUPS else None
    m = re.match(r"([0-9A-F ]+?)\s*; fully-qualified\s*# \S+ E\S+ (.*)", line)
    if not m or group is None:
        continue
    seq = "".join(chr(int(c, 16)) for c in m[1].split())
    if any(t in seq for t in TONES):
        # only one tone throughout: mixed pairs would need a second picker
        base = seq
        for t in TONES:
            base = base.replace(t, "")
        if "\U0001F3FB" in seq and not any(t in seq for t in TONES[1:]):
            tone_of[base.replace("️", "")] = seq
        continue
    words = set(fold(m[2]))
    for a in ann:
        for w in a.get(seq.replace("️", ""), []):
            words.update(fold(w))
    entries.append((group, seq, sorted(words, key=lambda w: (len(w), w))))
with open(out, "w", encoding="utf-8", newline="\n") as f:
    for g, seq, words in entries:
        f.write(f"{g}\t{seq}\t{tone_of.get(seq.replace(chr(0xFE0F), ''), '')}\t{' '.join(words)}\n")
print(len(entries), "emoji,", sum(1 for e in entries if e[1].replace(chr(0xFE0F), "") in tone_of), "with skin tones")
