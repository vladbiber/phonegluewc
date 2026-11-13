# screen text: libwayland-client and freetype; tesseract and the translator run only on demand
CC ?= cc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-format-truncation
CPPFLAGS += $$($(PKG_CONFIG) --cflags freetype2 wayland-client) -I.
LDLIBS = $$($(PKG_CONFIG) --libs freetype2 wayland-client) -lm
WP = $$($(PKG_CONFIG) --variable=pkgdatadir wayland-protocols)
GEN = wlr-layer-shell-unstable-v1 wlr-screencopy-unstable-v1 xdg-shell viewporter
PROTO_C = $(GEN:=-protocol.c)
PROTO_H = $(GEN:=-client-protocol.h)
PROTO_O = $(GEN:=-protocol.o)

all: phonetext test-ocr

phonetext: phonetext.o ocr.o $(PROTO_O)
	$(CC) $(CFLAGS) -o $@ phonetext.o ocr.o $(PROTO_O) $(LDLIBS)
test-ocr: test-ocr.o ocr.o
	$(CC) $(CFLAGS) -o $@ test-ocr.o ocr.o
phonetext.o: phonetext.c ocr.h ../keyboard/draw.h $(PROTO_H)
ocr.o: ocr.c ocr.h
test-ocr.o: test-ocr.c ocr.h

wlr-layer-shell-unstable-v1.xml: ; cp ../protocols/$@ $@
wlr-screencopy-unstable-v1.xml: ; cp ../tests/$@ $@
xdg-shell.xml: ; cp $(WP)/stable/xdg-shell/$@ $@
viewporter.xml: ; cp $(WP)/stable/viewporter/$@ $@
%-client-protocol.h: %.xml ; wayland-scanner client-header $< $@
%-protocol.c: %.xml ; wayland-scanner private-code $< $@
%-protocol.o: %-protocol.c %-client-protocol.h ; $(CC) $(CFLAGS) $$($(PKG_CONFIG) --cflags wayland-client) -c $< -o $@

check: test-ocr
	./test-ocr
clean:
	rm -f phonetext test-ocr *.o *-protocol.c *-client-protocol.h *.xml
.PHONY: all check clean
.SECONDARY:
