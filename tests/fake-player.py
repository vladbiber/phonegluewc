#!/usr/bin/env python3
# A fake MPRIS player for the tests and the laptop demo: art, length, seek, no sound.
import sys, time, gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

XML = """<node>
<interface name="org.mpris.MediaPlayer2">
<method name="Raise"/><method name="Quit"/>
<property name="CanRaise" type="b" access="read"/><property name="CanQuit" type="b" access="read"/>
<property name="Identity" type="s" access="read"/><property name="DesktopEntry" type="s" access="read"/>
<property name="HasTrackList" type="b" access="read"/>
<property name="SupportedUriSchemes" type="as" access="read"/><property name="SupportedMimeTypes" type="as" access="read"/>
</interface>
<interface name="org.mpris.MediaPlayer2.Player">
<method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/><method name="Stop"/><method name="Play"/>
<method name="Seek"><arg name="o" type="x" direction="in"/></method>
<method name="SetPosition"><arg name="t" type="o" direction="in"/><arg name="p" type="x" direction="in"/></method>
<signal name="Seeked"><arg name="p" type="x"/></signal>
<property name="PlaybackStatus" type="s" access="read"/><property name="Metadata" type="a{sv}" access="read"/>
<property name="Position" type="x" access="read"/><property name="Rate" type="d" access="read"/><property name="Volume" type="d" access="readwrite"/>
<property name="MinimumRate" type="d" access="read"/><property name="MaximumRate" type="d" access="read"/>
<property name="CanGoNext" type="b" access="read"/><property name="CanGoPrevious" type="b" access="read"/>
<property name="CanPlay" type="b" access="read"/><property name="CanPause" type="b" access="read"/>
<property name="CanSeek" type="b" access="read"/><property name="CanControl" type="b" access="read"/>
</interface></node>"""
TRACKS = [("Night Drive", "The Sample Band"), ("A much longer title that has to elide somewhere on the card", "Someone With A Long Name")]
art = sys.argv[1] if len(sys.argv) > 1 else ""
log = sys.argv[2] if len(sys.argv) > 2 else ""
state = {"playing": True, "track": 0, "pos": 12.0, "at": time.time()}
conn = None

def pos():
    return state["pos"] + (time.time() - state["at"] if state["playing"] else 0)
def setpos(s):
    state["pos"], state["at"] = s, time.time()
def meta():
    t = TRACKS[state["track"]]
    m = {"mpris:trackid": GLib.Variant("o", "/track/%d" % state["track"]), "mpris:length": GLib.Variant("x", 214000000),
         "xesam:title": GLib.Variant("s", t[0]), "xesam:artist": GLib.Variant("as", [t[1]])}
    if art:
        m["mpris:artUrl"] = GLib.Variant("s", "file://" + art)
    return m
def changed():
    conn.emit_signal(None, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "PropertiesChanged", GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", {
        "PlaybackStatus": GLib.Variant("s", "Playing" if state["playing"] else "Paused"), "Metadata": GLib.Variant("a{sv}", meta())}, [])))
def method(c, sender, path, iface, name, args, inv):
    if log:
        open(log, "a").write("player %s %s\n" % (name, args.unpack() if args else ""))
    if name in ("Play", "Pause", "PlayPause", "Stop"):
        setpos(pos())
        state["playing"] = name == "Play" or (name == "PlayPause" and not state["playing"])
    elif name in ("Next", "Previous"):
        state["track"] = (state["track"] + 1) % len(TRACKS)
        setpos(0)
    elif name == "SetPosition":
        setpos(args.unpack()[1] / 1e6)
        c.emit_signal(None, path, iface, "Seeked", GLib.Variant("(x)", (int(pos() * 1e6),)))
    elif name == "Seek":
        setpos(pos() + args.unpack()[0] / 1e6)
        c.emit_signal(None, path, iface, "Seeked", GLib.Variant("(x)", (int(pos() * 1e6),)))
    elif name == "Quit":
        loop.quit()
    inv.return_value(None)
    changed()
def prop(c, sender, path, iface, name):
    fixed = {"CanRaise": ("b", False), "CanQuit": ("b", True), "Identity": ("s", "Sample Music"), "DesktopEntry": ("s", "sample-music"), "HasTrackList": ("b", False),
             "SupportedUriSchemes": ("as", []), "SupportedMimeTypes": ("as", []), "Rate": ("d", 1.0), "Volume": ("d", 1.0), "MinimumRate": ("d", 1.0), "MaximumRate": ("d", 1.0),
             "CanGoNext": ("b", True), "CanGoPrevious": ("b", True), "CanPlay": ("b", True), "CanPause": ("b", True), "CanSeek": ("b", True), "CanControl": ("b", True)}
    if name == "PlaybackStatus":
        return GLib.Variant("s", "Playing" if state["playing"] else "Paused")
    if name == "Metadata":
        return GLib.Variant("a{sv}", meta())
    if name == "Position":
        return GLib.Variant("x", int(pos() * 1e6))
    return GLib.Variant(*fixed[name])

conn = Gio.bus_get_sync(Gio.BusType.SESSION)
for i in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
    conn.register_object("/org/mpris/MediaPlayer2", i, method, prop)
Gio.bus_own_name_on_connection(conn, "org.mpris.MediaPlayer2.samplemusic", 0, None, None)
loop = GLib.MainLoop()
loop.run()
