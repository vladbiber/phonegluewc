import subprocess, sys, collections
for f in sys.argv[1:]:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "frame=pts_time", "-of", "csv=p=0", f], capture_output=True, text=True).stdout
    t = [float(x.strip(",")) for x in out.split() if x.strip(",")]
    d = [round((b - a) * 1000) for a, b in zip(t, t[1:])]
    h = collections.Counter((x + 2) // 5 * 5 for x in d)
    print(f.split("/")[-1], "frames", len(t), "dur %.2f" % (t[-1] - t[0]), "fps %.2f" % (len(d) / (t[-1] - t[0])), "gap ms histogram", sorted(h.items()))
