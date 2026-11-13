#!/usr/bin/env python3
# fake-lang-server.py DIR PACKS [ui]: a local stand-in for the model registry and the pack host; prints each request
import hashlib, http.server, json, os, sys, time
out, packs, ui = sys.argv[1], sys.argv[2], sys.argv[3:] == ["ui"]
os.makedirs(out, exist_ok=True)
TAIL = b"\0\0enc-depth: 6\ndec-depth: %d\ntied-embeddings-all: true\n\0"
files, recs = {}, []
def rec(frm, to, typ, data, ver="1.0", hash=None, loc=None, **extra):
    loc = loc or f"m/{frm}-{to}-{ver}-{typ}"
    files[loc] = data
    r = {"fromLang": frm, "toLang": to, "version": ver, "fileType": typ, "name": typ,
         "attachment": {"hash": hash or hashlib.sha256(data).hexdigest(), "size": len(data), "location": loc}}
    r.update(extra)
    recs.append(r)
def pair(frm, to, dec=2, size=2000, **kw):
    rec(frm, to, "model", b"m" * size + TAIL % dec, **kw)
    rec(frm, to, "lex", b"l" * 300, ver=kw.get("ver", "1.0"))
    rec(frm, to, "vocab", b"v" * 300, ver=kw.get("ver", "1.0"))
for a, b in (("en", "de"), ("de", "en")):
    pair(a, b, dec=4)
for a, b in (("en", "ro"), ("ro", "en")):
    pair(a, b)
if not ui:
    pair("en", "bh", hash="0" * 64)
    pair("en", "ct", size=100000)
    pair("en", "sl", size=400000)
    pair("en", "ug", dec=6)
    pair("en", "pk")
    # never to be offered
    pair("en", "../../evil")
    pair("en", "al", ver="1.0a1")
    rec("en", "tr", "model", b"x" * 100, loc="../../outside")
    # a separate vocabulary per side does not load in this translator
    rec("en", "ja", "model", b"m" * 100)
    rec("en", "ja", "lex", b"l" * 100)
    rec("en", "ja", "srcvocab", b"v" * 100)
    rec("en", "ja", "trgvocab", b"v" * 100)
index = []
for name in ("words.tsv", "bigrams.tsv", "letters"):
    b = open(f"{packs}/ro/{name}", "rb").read()
    files[f"packs/ro/{name}"] = b
    index.append(f"ro\t{name}\t{len(b)}\t{hashlib.sha256(b).hexdigest()}\n")
if not ui:
    bad = {"words.tsv": b"not a word list\n", "bigrams.tsv": b"x\n", "letters": b"a\ta\tA\n"}
    for name, b in bad.items():
        files[f"packs/pk/{name}"] = b
        index.append(f"pk\t{name}\t{len(b)}\t{hashlib.sha256(b).hexdigest()}\n")
files["packs/index.tsv"] = "".join(index).encode()
files["records"] = json.dumps({"data": recs}).encode()
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        print(self.path, flush=True)
        key = self.path[1:]
        key = key[4:] if key.startswith("cdn/") else key
        data = files.get(key)
        if data is None:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            if "-ct-" in key and "model" in key:
                self.wfile.write(data[:len(data) // 2])  # the connection drops half way
            elif "-sl-" in key and "model" in key:
                for i in range(0, len(data), 4096):
                    self.wfile.write(data[i:i + 4096])
                    self.wfile.flush()
                    time.sleep(0.2)
            else:
                self.wfile.write(data)
        except OSError:
            pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
with open(f"{out}/port.tmp", "w") as f:
    f.write(str(srv.server_address[1]))
os.rename(f"{out}/port.tmp", f"{out}/port")
srv.serve_forever()
