# on-screen keyboard: libwayland-client and freetype, nothing else
CC ?= cc
PKG_CONFIG ?= pkg-config
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Wno-format-truncation
CPPFLAGS += $$($(PKG_CONFIG) --cflags freetype2 wayland-client) -I.
ifneq ($(KBD_DATADIR),)
CPPFLAGS += -DDATADIR=\"$(KBD_DATADIR)\"
endif
LDLIBS = $$($(PKG_CONFIG) --libs freetype2 wayland-client) -lm
WP = $$($(PKG_CONFIG) --variable=pkgdatadir wayland-protocols)
GEN = wlr-layer-shell-unstable-v1 input-method-unstable-v2 virtual-keyboard-unstable-v1 xdg-shell fractional-scale-v1 viewporter wlr-data-control-unstable-v1 wlr-foreign-toplevel-management-unstable-v1
PROTO_C = $(GEN:=-protocol.c)
PROTO_H = $(GEN:=-client-protocol.h)
PROTO_O = $(GEN:=-protocol.o)

all: phonekbd phonekbd-lang test-words test-emoji eval-words

phonekbd: phonekbd.o words.o emoji.o $(PROTO_O)
	$(CC) $(CFLAGS) -o $@ phonekbd.o words.o emoji.o $(PROTO_O) $(LDLIBS)
phonekbd-lang: phonekbd-lang.c langnames.h
	$(CC) $(CFLAGS) -I. $(if $(KBD_DATADIR),-DDATADIR=\"$(KBD_DATADIR)\") -o $@ phonekbd-lang.c
eval-words: eval-words.o words.o
	$(CC) $(CFLAGS) -o $@ eval-words.o words.o -lm
test-words: test-words.o words.o
	$(CC) $(CFLAGS) -o $@ test-words.o words.o -lm
test-emoji: test-emoji.o emoji.o words.o
	$(CC) $(CFLAGS) -o $@ test-emoji.o emoji.o words.o $(LDLIBS)
phonekbd.o: phonekbd.c draw.h words.h emoji.h $(PROTO_H)
words.o: words.c words.h
emoji.o: emoji.c emoji.h words.h
test-words.o: test-words.c words.h
eval-words.o: eval-words.c words.h
test-emoji.o: test-emoji.c emoji.h words.h

wlr-layer-shell-unstable-v1.xml: ; cp ../protocols/$@ $@
wlr-data-control-unstable-v1.xml: ; cp ../protocols/$@ $@
wlr-foreign-toplevel-management-unstable-v1.xml: ; cp ../protocols/$@ $@
input-method-unstable-v2.xml: ; cp ../tests/$@ $@
virtual-keyboard-unstable-v1.xml: ; cp ../tests/$@ $@
xdg-shell.xml: ; cp $(WP)/stable/xdg-shell/$@ $@
fractional-scale-v1.xml: ; cp $(WP)/staging/fractional-scale/$@ $@
viewporter.xml: ; cp $(WP)/stable/viewporter/$@ $@
%-client-protocol.h: %.xml ; wayland-scanner client-header $< $@
%-protocol.c: %.xml ; wayland-scanner private-code $< $@
%-protocol.o: %-protocol.c %-client-protocol.h ; $(CC) $(CFLAGS) $$($(PKG_CONFIG) --cflags wayland-client) -c $< -o $@

# the merged data is what a phone holds once Romanian is installed
check: test-words test-emoji phonekbd-lang eval-words
	rm -rf .check; mkdir -p .check/phonekbd/langs; cp -r packs/ro .check/phonekbd/langs/
	XDG_DATA_HOME=$$PWD/.check PHONEKBD_DATA=data ./phonekbd-lang merge
	./test-words .check/phonekbd/words.tsv .check/phonekbd/bigrams.tsv
	# hit rates on real phrases: floors just under what was measured
	./eval-words data/words.tsv data/bigrams.tsv data/eval/en.txt en 68 30 100 95
	./eval-words .check/phonekbd/words.tsv .check/phonekbd/bigrams.tsv data/eval/en.txt "en ro" 64 30 100 95
	./eval-words .check/phonekbd/words.tsv .check/phonekbd/bigrams.tsv data/eval/ro.txt "en ro" 43 30 100 95
	rm -rf .check
	./test-emoji data/emoji.tsv
clean:
	rm -rf .check; rm -f phonekbd phonekbd-lang eval-words test-words test-emoji *.o *-protocol.c *-client-protocol.h *.xml
.PHONY: all check clean
.SECONDARY:
