"""Generates the Chillara icon SVGs (432x432 adaptive-icon canvas).

Run:  python3 make_icon.py
Then render the Android PNGs with ImageMagick, e.g. for xxxhdpi
(adaptive layers are 108dp, legacy icon 48dp; scale per density):
  magick -background none -density 600 foreground.svg -resize 432x432 \
      ../../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png
  magick -background none -density 600 icon.svg -resize 192x192 \
      ../../android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
"""

GOLD_TOP, GOLD_SIDE, GOLD_RIM = "#f6c84f", "#d99a2b", "#b07818"
COIN_FACE, COIN_RING, RUPEE = "#f7cb55", "#dba235", "#9a6414"
GREEN_A, GREEN_B = "#5c8f4f", "#2f5530"

RUPEE_PATH = ("M181,152 H251 M181,176 H251 M181,152 H204 "
              "C234,152 234,202 204,202 H186 L238,248")
GLYPH = "translate(256,204) scale(0.72) translate(-216,-200)"

def stack(fill_top, fill_side, rim, gap=None):
    """Three flat coins, bottom first. gap: colour of the line between coins."""
    out = []
    cx, rx, ry, t = 182, 64, 19, 20
    for top in (282, 260, 238):
        side = (f"M{cx-rx},{top} V{top+t} A{rx},{ry} 0 0 0 {cx+rx},{top+t} "
                f"V{top} Z")
        out.append(f'<path d="{side}" fill="{fill_side}" stroke="{rim}" stroke-width="3"/>')
        out.append(f'<ellipse cx="{cx}" cy="{top}" rx="{rx}" ry="{ry}" fill="{fill_top}" stroke="{rim}" stroke-width="3"/>')
        if gap:
            out.append(f'<path d="M{cx-rx},{top+t} A{rx},{ry} 0 0 0 {cx+rx},{top+t}" fill="none" stroke="{gap}" stroke-width="4"/>')
    return "\n  ".join(out)

def big_coin(face, ring, glyph, rim):
    return f'''<circle cx="256" cy="208" r="74" fill="{rim}"/>
  <circle cx="256" cy="202" r="74" fill="{face}" stroke="{rim}" stroke-width="3"/>
  <circle cx="256" cy="202" r="58" fill="none" stroke="{ring}" stroke-width="6"/>
  <path d="{RUPEE_PATH}" transform="{GLYPH}" fill="none" stroke="{glyph}"
        stroke-width="19" stroke-linecap="round" stroke-linejoin="round"/>'''

# Fills the adaptive safe zone (radius 132 of 432) without crossing it.
SCALE = "translate(216,216) scale(1.08) translate(-216,-216)"

GLINT = ("M222,146 Q224,158 236,160 Q224,162 222,174 "
         "Q220,162 208,160 Q220,158 222,146 Z")

def foreground():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">
  <g transform="{SCALE}">
  <g opacity="0.22" transform="translate(4,10)" fill="#000">
    <ellipse cx="182" cy="302" rx="66" ry="21"/><circle cx="256" cy="206" r="76"/>
  </g>
  {stack(GOLD_TOP, GOLD_SIDE, GOLD_RIM)}
  {big_coin(COIN_FACE, COIN_RING, RUPEE, GOLD_RIM)}
  <path d="{GLINT}" fill="#fff8e1"/>
  </g>
</svg>'''

def background():
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{GREEN_A}"/><stop offset="1" stop-color="{GREEN_B}"/></linearGradient></defs>
  <rect width="432" height="432" fill="url(#g)"/>
</svg>'''

def monochrome():
    # White silhouette; details are cut out so themed icons stay readable.
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432">
  <defs><mask id="m"><g transform="{SCALE}">
    {stack("#fff", "#fff", "#fff", gap="#000")}
    <circle cx="256" cy="202" r="84" fill="#000"/>
    <circle cx="256" cy="202" r="74" fill="#fff"/>
    <circle cx="256" cy="202" r="58" fill="none" stroke="#000" stroke-width="6"/>
    <path d="{RUPEE_PATH}" transform="{GLYPH}" fill="none" stroke="#000"
          stroke-width="19" stroke-linecap="round" stroke-linejoin="round"/>
  </g></mask></defs>
  <rect width="432" height="432" fill="#fff" mask="url(#m)"/>
</svg>'''

def full_icon():
    # Rounded-square version (legacy launchers, README, store):
    # the visible 72/108 centre of the adaptive canvas.
    fg = foreground().split(">", 1)[1].rsplit("</svg>", 1)[0]
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="72 72 288 288">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{GREEN_A}"/><stop offset="1" stop-color="{GREEN_B}"/></linearGradient>
    <clipPath id="c"><rect x="72" y="72" width="288" height="288" rx="64"/></clipPath>
  </defs>
  <g clip-path="url(#c)">
    <rect x="72" y="72" width="288" height="288" fill="url(#g)"/>
    {fg}
  </g>
</svg>'''

for name, fn in [("foreground", foreground), ("background", background),
                 ("monochrome", monochrome), ("icon", full_icon)]:
    with open(f"{name}.svg", "w") as f:
        f.write(fn() + "\n")
print("written")
