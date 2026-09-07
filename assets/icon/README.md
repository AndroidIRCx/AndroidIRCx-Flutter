# Launcher icon assets

The adaptive launcher icon is generated **manually** with ImageMagick from two
source assets in this folder (the `flutter_launcher_icons` package's 0.14.x
build-hooks path was broken, so we generate the resources directly):

- `ic_launcher_foreground.png` — 1024×1024, transparent, the logo **mark only**
  (chat bubble + robot "A"), centered inside the adaptive-icon safe zone. No
  wordmark, no Flutter badge. This was extracted from `secrets/AndroidIRCx-Flutter.png`
  by cropping the mark and flood-filling the lavender card background to alpha.
- `ic_launcher_legacy.png` — 1024×1024, the same mark composited on the brand
  background `#F8F9FE` (used for the pre-Android-8 square icon).

## Generated resources (do not edit by hand)

- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` +
  `ic_launcher_round.xml` — adaptive-icon (background color + foreground).
- `android/app/src/main/res/values/ic_launcher_background.xml` — the `#F8F9FE`
  background color.
- `android/app/src/main/res/mipmap-{m,h,xh,xxh,xxx}dpi/` —
  `ic_launcher.png` (48–192), `ic_launcher_round.png` (48–192),
  `ic_launcher_foreground.png` (108–432).

## Regenerate (after replacing a source asset)

```bash
FG=assets/icon/ic_launcher_foreground.png
LG=assets/icon/ic_launcher_legacy.png
RES=android/app/src/main/res
gen() { d=$1; fg=$2; lg=$3; D="$RES/mipmap-$d";
  magick "$FG" -resize ${fg}x${fg} "$D/ic_launcher_foreground.png";
  magick "$LG" -resize ${lg}x${lg} "$D/ic_launcher.png";
  magick "$LG" -resize ${lg}x${lg} -alpha set \
    \( -size ${lg}x${lg} xc:none -fill white \
       -draw "circle $((lg/2)),$((lg/2)) $((lg/2)),0" \) \
    -compose DstIn -composite "$D/ic_launcher_round.png"; }
gen mdpi 108 48; gen hdpi 162 72; gen xhdpi 216 96; gen xxhdpi 324 144; gen xxxhdpi 432 192
```

After regenerating, do a **full rebuild** (not hot reload) — launcher icons are
native resources baked at build time.
