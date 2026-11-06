"""Genera el ícono y la pantalla de inicio (assets/*.png) de VidaMayor
a partir del logo oficial que está en design/.

  design/logo-abuelitos.png  -> los abuelitos entre las manos (fondo transparente)
  design/marca.png           -> la palabra "VidaMayor" y el lema

Uso: python3 scripts/make-icons.py   (requiere Pillow)
Después, `capacitor-assets generate --android` los convierte en los recursos de Android."""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DESIGN = os.path.join(HERE, "..", "design")
OUT = os.path.join(HERE, "..", "assets")
os.makedirs(OUT, exist_ok=True)

CREAM = (253, 251, 238)   # mismo crema del logo original
DEEP = (31, 79, 74)

logo = Image.open(os.path.join(DESIGN, "logo-abuelitos.png")).convert("RGBA")
marca = Image.open(os.path.join(DESIGN, "marca.png")).convert("RGB")


def fit_width(img, w):
    return img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)


def paste_center(base, img, cx, cy):
    x = round(cx - img.width / 2); y = round(cy - img.height / 2)
    if img.mode == "RGBA":
        base.alpha_composite(img, (x, y))
    else:
        base.paste(img, (x, y))


def save(img, name):
    img.convert("RGBA").save(os.path.join(OUT, name))
    print("ok", name, img.size)


S = 1024

# Ícono completo (versión antigua del launcher): logo grande sobre crema
im = Image.new("RGBA", (S, S), CREAM + (255,))
paste_center(im, fit_width(logo, 840), S / 2, S / 2)
save(im, "icon-only.png")

# Capa frontal del ícono adaptable: debe caber en la zona segura (~66 %)
im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
paste_center(im, fit_width(logo, 680), S / 2, S / 2)
save(im, "icon-foreground.png")

# Capa de fondo del ícono adaptable
save(Image.new("RGBA", (S, S), CREAM + (255,)), "icon-background.png")


def splash(name, dark=False):
    N = 2732
    im = Image.new("RGBA", (N, N), (DEEP if dark else CREAM) + (255,))
    lg = fit_width(logo, 740)
    mk = fit_width(marca, 1040)
    gap = 40
    total = lg.height + gap + mk.height
    if dark:  # tarjeta crema para que el logo se lea sobre el fondo oscuro
        card_w, card_h = 1240, total + 200
        card = Image.new("RGBA", (card_w * 2, card_h * 2), (0, 0, 0, 0))
        ImageDraw.Draw(card).rounded_rectangle((0, 0, card_w * 2 - 1, card_h * 2 - 1),
                                               radius=150, fill=CREAM + (255,))
        card = card.resize((card_w, card_h), Image.LANCZOS)
        paste_center(im, card, N / 2, N / 2)
    top = N / 2 - total / 2
    paste_center(im, lg, N / 2, top + lg.height / 2)
    paste_center(im, mk, N / 2, top + lg.height + gap + mk.height / 2)
    save(im, name)


splash("splash.png")
splash("splash-dark.png", dark=True)
