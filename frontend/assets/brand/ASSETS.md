# Brand images (not model-generated)

Geometric notebook mark. Canvas `#0E0E0D`, ink `#F3F1EE`. Source: `mark.svg` + `tool/render_brand.py`.

## In the running app

Drawn with `BrandMark` on the sign-in screen. Do not drop photos, mascots, or 3D brains into chat/library.

## Copy into your Flutter tree (after `flutter create`)

### Web (tab + PWA)

From `frontend/web/` in this pack into your `frontend/web/`:

| File | Role |
| --- | --- |
| `favicon.png` | Browser tab |
| `apple-touch-icon.png` | iOS “Add to Home Screen” |
| `icons/Icon-192.png` | PWA |
| `icons/Icon-512.png` | PWA |
| `icons/Icon-maskable-192.png` | Android adaptive PWA |
| `icons/Icon-maskable-512.png` | Android adaptive PWA |
| `manifest.json` | PWA name/colors |

In `web/index.html` add the lines from `web/index.html.snippet`.

### Android launcher

Copy each `assets/brand/android/mipmap-*/ic_launcher.png` over:

`android/app/src/main/res/mipmap-*/ic_launcher.png`

Optional adaptive: `assets/brand/adaptive-foreground-1024.png` as foreground, background color `#0E0E0D`.

Play Store: `assets/brand/icon-512.png`.

### iOS App Icon

Copy `assets/brand/ios/AppIcon-*.png` into:

`ios/Runner/Assets.xcassets/AppIcon.appiconset/`

Match sizes in that folder’s `Contents.json` (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024).

App Store: `AppIcon-1024.png`.

## What we did **not** add

Splash illustrations, empty-state cartoons, OG social cards, notification badges. Those would look like clip-art. Empty states stay text.
