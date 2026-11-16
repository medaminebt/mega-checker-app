# dmgbuild settings for the macOS installer window (run by tool/make_dmg.sh).
#
# The icon positions match the artwork drawn by
# tool/generate_dmg_background.swift (appX, appsX, iconY).
import os.path

app = defines["app"]  # noqa: F821  (dmgbuild provides `defines`)
appname = os.path.basename(app)

format = "UDZO"  # compressed, opens on every macOS version
files = [app]
symlinks = {"Applications": "/Applications"}
# No hide_extensions: it sets Finder flags on the app bundle, which breaks a
# strict signature check. Finder hides ".app" by default anyway.

icon = defines.get("volume_icon")  # noqa: F821  (the disk's own icon)
background = defines["background"]  # noqa: F821  (1x + 2x TIFF)

# 452 = 420 pt of artwork + Finder's 32 pt title bar (macOS 26/27). The
# background is 460 tall, so a shorter title bar just shows more of it.
window_rect = ((300, 300), (660, 452))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {
    appname: (160, 212),
    "Applications": (500, 212),
}
