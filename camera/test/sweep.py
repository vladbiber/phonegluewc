import subprocess, sys, numpy as np, cv2, os, time
P = "/sys/module/camu_lens/parameters/pos"
def lens(pos): open(P, "w").write(str(pos))
exp, gain = sys.argv[1], sys.argv[2]
for pos in [int(a) for a in sys.argv[3:]]:
    lens(pos); time.sleep(0.1)
    g = subprocess.run([os.path.expanduser("~/camtest/app/phonecam-raw"), "back", "bin", "1", exp, gain, "/tmp/sw.raw"], capture_output=True, text=True)
    if g.returncode: print(g.stderr); break
    w, h, stride = map(int, g.stdout.split()[:3])
    f = np.fromfile("/tmp/sw.raw", np.uint8)[:stride*h].reshape(h, stride)[:, :w*5//4].reshape(h, w//4, 5)[:, :, :4].reshape(h, w)
    gr = cv2.GaussianBlur(f[0::2, 0::2].astype(np.float32), (0, 0), 1.0)  # one Bayer plane
    out = []
    for name, (y0, y1, x0, x1) in {"centre": (.35, .65, .35, .65), "left": (.3, .7, .05, .3), "right": (.3, .7, .7, .95)}.items():
        c = gr[int(y0*gr.shape[0]):int(y1*gr.shape[0]), int(x0*gr.shape[1]):int(x1*gr.shape[1])]
        out.append("%s %.2f" % (name, (cv2.Sobel(c, cv2.CV_32F, 1, 0)**2 + cv2.Sobel(c, cv2.CV_32F, 0, 1)**2).mean()))
    print(pos, "mean %.1f" % gr.mean(), *out, flush=True)
    cv2.imwrite(f"/tmp/sw{pos}.jpg", np.clip(cv2.resize(gr, None, fx=.5, fy=.5, interpolation=cv2.INTER_AREA) * 3, 0, 255).astype(np.uint8))
lens(-1)
os.unlink("/tmp/sw.raw")
