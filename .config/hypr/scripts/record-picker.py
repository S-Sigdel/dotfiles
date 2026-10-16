#!/usr/bin/env python3
"""Recorder dialog (used by record.sh).

  record-picker.py serve
      stay loaded in the background (started by hyprland.lua) and show dialogs
      on request over $XDG_RUNTIME_DIR/record/picker.sock - instant, no GTK cold start
  record-picker.py pick --monitors "eDP-1 HDMI-A-1" [--what area] [--desk 1] [--mic 0]
      one window: what to record + sound toggles + Record.
      prints "WHAT DESK MIC" (WHAT = area | full:<monitor>), exit 1 on cancel.
  record-picker.py countdown --label "Area · desktop + voice" [--seconds 3]
      big 3-2-1, closes itself; exit 1 if cancelled with Esc.

pick/countdown go through the background service when it's running, and fall
back to opening the window themselves when it isn't.
"""
import argparse, json, os, socket, sys

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "record", "picker.sock")

def parse(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["serve", "pick", "countdown"])
    ap.add_argument("--monitors", default="")
    ap.add_argument("--what", default="area")
    ap.add_argument("--desk", default="1")
    ap.add_argument("--mic", default="1")
    ap.add_argument("--label", default="")
    ap.add_argument("--seconds", type=int, default=3)
    return ap.parse_args(argv)

# ------------------------------------------------------------------ client
def via_service(argv):
    """Ask the background service; returns (code, output) or None if it isn't running."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(SOCK)
    except OSError:
        return None
    s.sendall((json.dumps(argv) + "\n").encode())
    data = b""
    while not data.endswith(b"\n"):
        chunk = s.recv(4096)
        if not chunk: break
        data += chunk
    s.close()
    reply = json.loads(data or b'{"code":1,"out":""}')
    return reply["code"], reply["out"]

# --------------------------------------------------------------------- GTK
CSS = b"""
window.rec { background: #121319; border: 1px solid rgba(255,255,255,0.08); border-radius: 18px; }
.rec * { font-family: "GeistMono Nerd Font", monospace; color: #c9ccd4; }
.title  { font-size: 16px; font-weight: 700; color: #e2e4ea; }
.hint   { font-size: 11px; color: #6e7585; }
.section{ font-size: 11px; font-weight: 700; color: #6e7585; margin-top: 6px; }
.opt { background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06);
       border-radius: 10px; padding: 9px 14px; box-shadow: none; }
.opt:hover   { background: rgba(255,255,255,0.08); }
.opt:checked { background: rgba(169,194,214,0.18); border-color: rgba(169,194,214,0.40); }
.opt:checked label { color: #e2e4ea; }
.cancel { background: transparent; border: none; box-shadow: none; padding: 9px 14px; border-radius: 10px; }
.cancel:hover { background: rgba(255,255,255,0.06); }
.go { background: rgba(208,138,138,0.20); border: 1px solid rgba(208,138,138,0.45);
      border-radius: 10px; padding: 9px 18px; box-shadow: none; }
.go:hover { background: rgba(208,138,138,0.30); }
.go label { color: #f0d4d4; font-weight: 700; }
.count { font-size: 72px; font-weight: 700; color: #e2e4ea; }
"""

def gtk_app(oneshot_args=None):
    import gi
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk, Gdk, GLib, Gio

    def box(orient=Gtk.Orientation.VERTICAL, spacing=8):
        return Gtk.Box(orientation=orient, spacing=spacing)

    class Dialog:
        """One window (picker or countdown); calls done(code, out) once."""
        def __init__(self, app, args, done):
            self.args, self.done, self.finished = args, done, False
            self.win = Gtk.ApplicationWindow(application=app, title="Record")
            self.win.add_css_class("rec"); self.win.set_decorated(False); self.win.set_resizable(False)
            keys = Gtk.EventControllerKey(); keys.connect("key-pressed", self.on_key); self.win.add_controller(keys)
            self.win.connect("close-request", self.on_close)
            (self.build_pick if args.mode == "pick" else self.build_countdown)()
            self.win.present()

        def on_close(self, *_):
            self.finish(1, ""); return True

        def finish(self, code, out):
            if self.finished: return
            self.finished = True
            self.win.destroy()
            self.done(code, out)

        # picker
        def build_pick(self):
            a = self.args
            root = box(spacing=10); root.set_margin_top(18); root.set_margin_bottom(16)
            root.set_margin_start(20); root.set_margin_end(20); root.set_size_request(440, -1)
            head = box(spacing=2)
            t = Gtk.Label(label="󰑊  Record", xalign=0); t.add_css_class("title")
            h = Gtk.Label(label="Enter to start · Esc to cancel · F9 again stops", xalign=0); h.add_css_class("hint")
            head.append(t); head.append(h); root.append(head)

            s1 = Gtk.Label(label="WHAT", xalign=0); s1.add_css_class("section"); root.append(s1)
            row = box(Gtk.Orientation.HORIZONTAL, 6); row.set_homogeneous(True)
            mons = a.monitors.split()
            whats = [("area", "󰩭  Area")] + [
                (f"full:{m}", "󰍹  Full screen" if len(mons) == 1 else f"󰍹  {m}") for m in mons]
            self.what_btns, group = {}, None
            for key, label in whats:
                b = Gtk.ToggleButton(label=label); b.add_css_class("opt")
                if group: b.set_group(group)
                else: group = b
                self.what_btns[key] = b; row.append(b)
            (self.what_btns.get(a.what) or self.what_btns["area"]).set_active(True)
            root.append(row)

            s2 = Gtk.Label(label="SOUND", xalign=0); s2.add_css_class("section"); root.append(s2)
            row2 = box(Gtk.Orientation.HORIZONTAL, 6); row2.set_homogeneous(True)
            self.desk = Gtk.ToggleButton(label="󰓃  Desktop sound"); self.desk.add_css_class("opt")
            self.mic = Gtk.ToggleButton(label="󰍬  My voice");      self.mic.add_css_class("opt")
            self.desk.set_active(a.desk == "1"); self.mic.set_active(a.mic == "1")
            row2.append(self.desk); row2.append(self.mic); root.append(row2)

            act = box(Gtk.Orientation.HORIZONTAL, 6); act.set_halign(Gtk.Align.END); act.set_margin_top(8)
            c = Gtk.Button(label="Cancel"); c.add_css_class("cancel"); c.connect("clicked", lambda *_: self.finish(1, ""))
            g = Gtk.Button(label="●  Record"); g.add_css_class("go"); g.connect("clicked", self.on_go)
            act.append(c); act.append(g); root.append(act)
            self.win.set_child(root)
            # must return False: grab_focus() returns True, which would re-run it forever
            GLib.idle_add(lambda: g.grab_focus() and False)

        def on_go(self, *_):
            what = next(k for k, b in self.what_btns.items() if b.get_active())
            self.finish(0, f"{what} {int(self.desk.get_active())} {int(self.mic.get_active())}")

        # countdown
        def build_countdown(self):
            root = box(spacing=0); root.set_size_request(260, 200)
            root.set_valign(Gtk.Align.CENTER); root.set_margin_top(22); root.set_margin_bottom(22)
            self.n = self.args.seconds
            self.num = Gtk.Label(label=str(self.n)); self.num.add_css_class("count")
            sub = Gtk.Label(label=self.args.label); sub.add_css_class("hint")
            hint = Gtk.Label(label="Esc to cancel"); hint.add_css_class("hint"); hint.set_margin_top(4)
            root.append(self.num); root.append(sub); root.append(hint)
            self.win.set_child(root)
            GLib.timeout_add(1000, self.tick)

        def tick(self):
            if self.finished: return False
            self.n -= 1
            if self.n <= 0:
                self.finish(0, ""); return False
            self.num.set_label(str(self.n)); return True

        def on_key(self, _c, keyval, _code, _state):
            if keyval == Gdk.KEY_Escape:
                self.finish(1, ""); return True
            if self.args.mode == "pick" and keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.on_go(); return True
            return False

    class App(Gtk.Application):
        def __init__(self):
            super().__init__(application_id="dev.local.recorder", flags=Gio.ApplicationFlags.NON_UNIQUE)
            self.code, self.out = 1, ""

        def do_startup(self):
            Gtk.Application.do_startup(self)
            p = Gtk.CssProvider(); p.load_from_data(CSS)
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), p,
                                                      Gtk.STYLE_PROVIDER_PRIORITY_USER)

        def do_activate(self):
            if oneshot_args:
                def done(code, out): self.code, self.out = code, out; self.quit()
                Dialog(self, oneshot_args, done)
            else:
                self.hold()                                   # stay alive with no windows
                self.listen()

        # background service: one JSON request line per connection, one JSON reply
        def listen(self):
            os.makedirs(os.path.dirname(SOCK), exist_ok=True)
            try: os.unlink(SOCK)
            except FileNotFoundError: pass
            self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.srv.bind(SOCK); self.srv.listen(4)
            # explicit (channel, priority, condition, callback) form - the short form
            # silently mis-binds the arguments and spins at 100% CPU
            self.chan = GLib.IOChannel.unix_new(self.srv.fileno())
            GLib.io_add_watch(self.chan, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN, self.on_conn)

        def on_conn(self, *_):
            conn, _ = self.srv.accept()
            data = b""
            while not data.endswith(b"\n"):
                chunk = conn.recv(4096)
                if not chunk: break
                data += chunk
            try:
                args = parse(json.loads(data))
            except (Exception, SystemExit):
                conn.close(); return True
            def done(code, out):
                try: conn.sendall((json.dumps({"code": code, "out": out}) + "\n").encode())
                except OSError: pass
                conn.close()
            Dialog(self, args, done)
            return True

    return App()

def main():
    argv = sys.argv[1:]
    args = parse(argv)
    if args.mode == "serve":
        gtk_app().run([]); return
    reply = via_service(argv)
    if reply is None:                                           # service not running: do it ourselves
        app = gtk_app(oneshot_args=args); app.run([])
        reply = (app.code, app.out)
    code, out = reply
    if out: print(out)
    sys.exit(code)

if __name__ == "__main__":
    main()
