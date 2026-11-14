.POSIX:
.SUFFIXES:

include config.mk

# flags for compiling
PHONEGLUEWCCPPFLAGS = -I. -DWLR_USE_UNSTABLE -D_POSIX_C_SOURCE=200809L \
	-DVERSION=\"$(VERSION)\" -DSHELLDIR=\"$(DATADIR)/phonegluewc/shell\" $(XWAYLAND)
PHONEGLUEWCDEVCFLAGS = -g -Wpedantic -Wall -Wextra -Wdeclaration-after-statement \
	-Wno-unused-parameter -Wshadow -Wunused-macros -Werror=strict-prototypes \
	-Werror=implicit -Werror=return-type -Werror=incompatible-pointer-types \
	-Wfloat-conversion

# CFLAGS / LDFLAGS
PKGS      = wayland-server xkbcommon libinput $(XLIBS)
PHONEGLUEWCCFLAGS = `$(PKG_CONFIG) --cflags $(PKGS)` $(SCENEFX_INCS) $(WLR_INCS) $(PHONEGLUEWCCPPFLAGS) $(PHONEGLUEWCDEVCFLAGS) $(CFLAGS)
LDLIBS    = `$(PKG_CONFIG) --libs $(PKGS)` $(SCENEFX_LIBS) $(WLR_LIBS) -lm $(LIBS)
# phonegluewc-msg is a plain Wayland client
MSGCFLAGS = `$(PKG_CONFIG) --cflags wayland-client` -I. $(PHONEGLUEWCDEVCFLAGS) $(CFLAGS)
MSGLIBS   = `$(PKG_CONFIG) --libs wayland-client` $(LIBS)

all: phonegluewc phonegluewc-msg phonecamera phonepin keyboard/phonekbd screentext/phonetext

check: phonegluewc
	sh -n install.sh phonegluewc-session phonegluewc-backlight phonegluewc-sensor tests/drm-test.sh settings/phonesettings settings/pset gallery/phonegallery gallery/phonegallery-android-apply waydroid/phone-waydroid-idle
	PHONEGALLERY_USER=$${USER:-root} python3 gallery/phonegallery-android --selfcheck >/dev/null 2>&1
	python3 gallery/phonegallery-albums --selfcheck
	$(MAKE) -C tests
HYPROBJS =
phonegluewc: phonegluewc.o util.o dwl-ipc-unstable-v2-protocol.o $(HYPROBJS)
	$(CC) phonegluewc.o util.o dwl-ipc-unstable-v2-protocol.o $(HYPROBJS) $(PHONEGLUEWCCFLAGS) $(LDFLAGS) $(LDLIBS) -o $@
phonegluewc-hyprctl: phonegluewc-hyprctl.c
	$(CC) $(CPPFLAGS) -D_POSIX_C_SOURCE=200809L $(PHONEGLUEWCDEVCFLAGS) $(CFLAGS) $(LDFLAGS) phonegluewc-hyprctl.c -o $@
phonecamera: phonecamera.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) phonecamera.c -o $@
phonepin: phonepin.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) phonepin.c -lcrypt -o $@
phonegluewc-msg: phonegluewc-msg.o dwl-ipc-unstable-v2-protocol.o wlr-output-power-management-unstable-v1-protocol.o
	$(CC) phonegluewc-msg.o dwl-ipc-unstable-v2-protocol.o wlr-output-power-management-unstable-v1-protocol.o $(MSGCFLAGS) $(LDFLAGS) $(MSGLIBS) -o $@
phonegluewc-msg.o: phonegluewc-msg.c dwl-ipc-unstable-v2-client-protocol.h \
	wlr-output-power-management-unstable-v1-client-protocol.h
	$(CC) $(CPPFLAGS) $(MSGCFLAGS) -o $@ -c phonegluewc-msg.c
phonegluewc.o: phonegluewc.c client.h config.h config.mk cursor-shape-v1-protocol.h \
	dwl-ipc-unstable-v2-protocol.h \
	pointer-constraints-unstable-v1-protocol.h wlr-layer-shell-unstable-v1-protocol.h \
	wlr-output-power-management-unstable-v1-protocol.h xdg-shell-protocol.h
util.o: util.c util.h
dwl-ipc-unstable-v2-protocol.o: dwl-ipc-unstable-v2-protocol.c dwl-ipc-unstable-v2-protocol.h
hyprland-toplevel-export-v1-protocol.o: hyprland-toplevel-export-v1-protocol.c
hyprland-toplevel-mapping-v1-protocol.o: hyprland-toplevel-mapping-v1-protocol.c
wlr-foreign-toplevel-management-unstable-v1-protocol.o: wlr-foreign-toplevel-management-unstable-v1-protocol.c
ext-foreign-toplevel-list-v1-protocol.o: ext-foreign-toplevel-list-v1-protocol.c
wlr-output-power-management-unstable-v1-protocol.o: wlr-output-power-management-unstable-v1-protocol.c
	$(CC) $(CPPFLAGS) $(MSGCFLAGS) -o $@ -c wlr-output-power-management-unstable-v1-protocol.c

# wayland-scanner is a tool which generates C headers and rigging for Wayland
# protocols, which are specified in XML. wlroots requires you to rig these up
# to your build system yourself and provide them in the include path.
WAYLAND_SCANNER   = `$(PKG_CONFIG) --variable=wayland_scanner wayland-scanner`
WAYLAND_PROTOCOLS = `$(PKG_CONFIG) --variable=pkgdatadir wayland-protocols`

cursor-shape-v1-protocol.h:
	$(WAYLAND_SCANNER) enum-header \
		$(WAYLAND_PROTOCOLS)/staging/cursor-shape/cursor-shape-v1.xml $@
pointer-constraints-unstable-v1-protocol.h:
	$(WAYLAND_SCANNER) enum-header \
		$(WAYLAND_PROTOCOLS)/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml $@
wlr-layer-shell-unstable-v1-protocol.h:
	$(WAYLAND_SCANNER) enum-header \
		protocols/wlr-layer-shell-unstable-v1.xml $@
wlr-output-power-management-unstable-v1-protocol.h:
	$(WAYLAND_SCANNER) server-header \
		protocols/wlr-output-power-management-unstable-v1.xml $@
wlr-output-power-management-unstable-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		protocols/wlr-output-power-management-unstable-v1.xml $@
wlr-output-power-management-unstable-v1-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		protocols/wlr-output-power-management-unstable-v1.xml $@
xdg-shell-protocol.h:
	$(WAYLAND_SCANNER) server-header \
		$(WAYLAND_PROTOCOLS)/stable/xdg-shell/xdg-shell.xml $@
dwl-ipc-unstable-v2-protocol.h:
	$(WAYLAND_SCANNER) server-header \
		protocols/dwl-ipc-unstable-v2.xml $@
dwl-ipc-unstable-v2-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		protocols/dwl-ipc-unstable-v2.xml $@
dwl-ipc-unstable-v2-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		protocols/dwl-ipc-unstable-v2.xml $@
hyprland-toplevel-export-v1-protocol.h:
	$(WAYLAND_SCANNER) server-header protocols/hyprland-toplevel-export-v1.xml $@
hyprland-toplevel-export-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code protocols/hyprland-toplevel-export-v1.xml $@
hyprland-toplevel-mapping-v1-protocol.h:
	$(WAYLAND_SCANNER) server-header protocols/hyprland-toplevel-mapping-v1.xml $@
hyprland-toplevel-mapping-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code protocols/hyprland-toplevel-mapping-v1.xml $@
wlr-foreign-toplevel-management-unstable-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code protocols/wlr-foreign-toplevel-management-unstable-v1.xml $@
ext-foreign-toplevel-list-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS)/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml $@

config.h:
	cp config.def.h $@
clean:
	rm -f phonegluewc phonegluewc-msg phonecamera phonepin phonegluewc-hyprctl *.o *-protocol.h *-protocol.c
	$(MAKE) -C keyboard clean
	$(MAKE) -C screentext clean

dist: clean
	mkdir -p phonegluewc-$(VERSION)
	cp -R .github docs LICENSE* Makefile CHANGELOG.md CONTRIBUTING.md \
		README.md SECURITY.md install.sh flake.nix client.h config.def.h \
		config.def.conf config.mk protocols phonegluewc.1 phonegluewc.c phonegluewc-msg.c phonecamera.c phonepin.c \
		hypr.c hyprexport.c phonegluewc-hyprctl.c \
		util.c util.h phonegluewc.desktop phonegluewc-session phonegluewc-backlight phonegluewc-sensor phonegluewc-$(VERSION)
	tar -caf phonegluewc-$(VERSION).tar.gz phonegluewc-$(VERSION)
	rm -rf phonegluewc-$(VERSION)

keyboard/phonekbd: FORCE
	$(MAKE) -C keyboard phonekbd phonekbd-lang KBD_DATADIR="$(DATADIR)/phonegluewc/keyboard"
screentext/phonetext: FORCE
	$(MAKE) -C screentext phonetext
FORCE:

install: phonegluewc phonegluewc-msg phonecamera phonepin keyboard/phonekbd screentext/phonetext
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	rm -f $(DESTDIR)$(PREFIX)/bin/phonegluewc $(DESTDIR)$(PREFIX)/bin/phonegluewc-msg
	cp -f phonegluewc $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegluewc
	cp -f phonegluewc-msg $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegluewc-msg
	cp -f phonecamera $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonecamera
	cp -f phonepin $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonepin
	cp -f phonegluewc-session $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegluewc-session
	cp -f phonegluewc-backlight $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegluewc-backlight
	cp -f phonegluewc-sensor $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegluewc-sensor
	mkdir -p $(DESTDIR)$(MANDIR)/man1
	cp -f phonegluewc.1 $(DESTDIR)$(MANDIR)/man1
	chmod 644 $(DESTDIR)$(MANDIR)/man1/phonegluewc.1
	mkdir -p $(DESTDIR)$(DATADIR)/phonegluewc
	cp -f config.def.conf $(DESTDIR)$(DATADIR)/phonegluewc/config.def.conf
	chmod 644 $(DESTDIR)$(DATADIR)/phonegluewc/config.def.conf
	cp -rf shell $(DESTDIR)$(DATADIR)/phonegluewc/
	cp -rf settings $(DESTDIR)$(DATADIR)/phonegluewc/
	cp -rf wallpapers $(DESTDIR)$(DATADIR)/phonegluewc/
	cp -f settings/phonesettings $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonesettings
	mkdir -p $(DESTDIR)$(DATADIR)/applications $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps
	cp -f settings/phonesettings.desktop $(DESTDIR)$(DATADIR)/applications
	chmod 644 $(DESTDIR)$(DATADIR)/applications/phonesettings.desktop
	cp -f settings/phonesettings.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps
	chmod 644 $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/phonesettings.svg
	cp -rf gallery $(DESTDIR)$(DATADIR)/phonegluewc/
	cp -f gallery/phonegallery $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegallery
	cp -f gallery/phonegallery.desktop $(DESTDIR)$(DATADIR)/applications
	chmod 644 $(DESTDIR)$(DATADIR)/applications/phonegallery.desktop
	cp -f gallery/phonegallery.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps
	chmod 644 $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/phonegallery.svg
	cp -f gallery/phonegallery-android $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegallery-android
	cp -f gallery/phonegallery-android-apply $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonegallery-android-apply
	mkdir -p $(DESTDIR)/etc/systemd/user/default.target.wants
	cp -f gallery/phonegallery-android.service $(DESTDIR)/etc/systemd/user
	cp -f gallery/phonegallery-android-refresh.service gallery/phonegallery-android-refresh.timer $(DESTDIR)/etc/systemd/user
	mkdir -p $(DESTDIR)/etc/systemd/user/timers.target.wants
	ln -sf /etc/systemd/user/phonegallery-android-refresh.timer $(DESTDIR)/etc/systemd/user/timers.target.wants/phonegallery-android-refresh.timer
	ln -sf /etc/systemd/user/phonegallery-android.service $(DESTDIR)/etc/systemd/user/default.target.wants/phonegallery-android.service
	mkdir -p $(DESTDIR)/etc/sudoers.d
	printf '%%wheel ALL=(root) NOPASSWD: $(PREFIX)/bin/phonegallery-android\n' > $(DESTDIR)/etc/sudoers.d/phonegallery-android
	chmod 440 $(DESTDIR)/etc/sudoers.d/phonegallery-android
	cp -f keyboard/phonekbd keyboard/phonekbd-lang $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonekbd $(DESTDIR)$(PREFIX)/bin/phonekbd-lang
	cp -f waydroid/phone-waydroid-idle $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phone-waydroid-idle
	mkdir -p $(DESTDIR)/etc/systemd/user
	cp -f waydroid/phone-waydroid-idle.service waydroid/phone-waydroid-idle.timer $(DESTDIR)/etc/systemd/user
	mkdir -p $(DESTDIR)/etc/systemd/user/timers.target.wants
	ln -sf /etc/systemd/user/phone-waydroid-idle.timer $(DESTDIR)/etc/systemd/user/timers.target.wants/phone-waydroid-idle.timer
	mkdir -p $(DESTDIR)$(DATADIR)/phonegluewc/android
	cp -f keyboard/android/phonekbd-bridge.apk $(DESTDIR)$(DATADIR)/phonegluewc/android
	chmod 644 $(DESTDIR)$(DATADIR)/phonegluewc/android/phonekbd-bridge.apk
	mkdir -p $(DESTDIR)$(DATADIR)/phonegluewc/keyboard
	cp -f keyboard/data/words.tsv keyboard/data/bigrams.tsv keyboard/data/emoji.tsv keyboard/data/SOURCES keyboard/data/LICENSE-UNICODE $(DESTDIR)$(DATADIR)/phonegluewc/keyboard
	cp -f screentext/phonetext screentext/phonetext-translate $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/phonetext $(DESTDIR)$(PREFIX)/bin/phonetext-translate
	mkdir -p $(DESTDIR)$(DATADIR)/doc/phonegluewc
	cp -f README.md CONTRIBUTING.md SECURITY.md $(DESTDIR)$(DATADIR)/doc/phonegluewc
	cp -R docs $(DESTDIR)$(DATADIR)/doc/phonegluewc
	mkdir -p $(DESTDIR)$(SESSIONDIR)
	cp -f phonegluewc.desktop $(DESTDIR)$(SESSIONDIR)/phonegluewc.desktop
	chmod 644 $(DESTDIR)$(SESSIONDIR)/phonegluewc.desktop
	sync
uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/phonegluewc $(DESTDIR)$(PREFIX)/bin/phonegluewc-session $(DESTDIR)$(PREFIX)/bin/phonegluewc-sensor \
		$(DESTDIR)$(PREFIX)/bin/phonegluewc-msg $(DESTDIR)$(PREFIX)/bin/phonecamera $(DESTDIR)$(PREFIX)/bin/phonepin $(DESTDIR)$(PREFIX)/bin/phonegluewc-hyprctl \
		$(DESTDIR)$(PREFIX)/bin/phonekbd $(DESTDIR)$(PREFIX)/bin/phonekbd-lang $(DESTDIR)$(PREFIX)/bin/phone-waydroid-idle \
		$(DESTDIR)/etc/systemd/user/phone-waydroid-idle.service $(DESTDIR)/etc/systemd/user/phone-waydroid-idle.timer $(DESTDIR)/etc/systemd/user/timers.target.wants/phone-waydroid-idle.timer $(DESTDIR)$(PREFIX)/bin/phonetext $(DESTDIR)$(PREFIX)/bin/phonetext-translate \
		$(DESTDIR)$(PREFIX)/bin/phonesettings $(DESTDIR)$(DATADIR)/applications/phonesettings.desktop \
		$(DESTDIR)$(PREFIX)/bin/phonegallery-android $(DESTDIR)/etc/sudoers.d/phonegallery-android \
		$(DESTDIR)$(PREFIX)/bin/phonegallery-android-apply $(DESTDIR)/etc/systemd/user/phonegallery-android.service $(DESTDIR)/etc/systemd/user/default.target.wants/phonegallery-android.service \
		$(DESTDIR)/etc/systemd/user/phonegallery-android-refresh.service $(DESTDIR)/etc/systemd/user/phonegallery-android-refresh.timer $(DESTDIR)/etc/systemd/user/timers.target.wants/phonegallery-android-refresh.timer \
		$(DESTDIR)$(PREFIX)/bin/phonegallery $(DESTDIR)$(DATADIR)/applications/phonegallery.desktop \
		$(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/phonegallery.svg \
		$(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/phonesettings.svg \
		$(DESTDIR)$(MANDIR)/man1/phonegluewc.1 \
		$(DESTDIR)$(DATADIR)/phonegluewc/config.def.conf \
		$(DESTDIR)$(SESSIONDIR)/phonegluewc.desktop
	rm -rf $(DESTDIR)$(DATADIR)/doc/phonegluewc $(DESTDIR)$(PREFIX)/lib/phonegluewc $(DESTDIR)$(DATADIR)/phonegluewc/keyboard \
		$(DESTDIR)$(DATADIR)/phonegluewc/settings $(DESTDIR)$(DATADIR)/phonegluewc/gallery $(DESTDIR)$(DATADIR)/phonegluewc/wallpapers \
		$(DESTDIR)$(DATADIR)/phonegluewc/android

.PHONY: all check clean dist install uninstall FORCE

.SUFFIXES: .c .o
.c.o:
	$(CC) $(CPPFLAGS) $(PHONEGLUEWCCFLAGS) -o $@ -c $<
