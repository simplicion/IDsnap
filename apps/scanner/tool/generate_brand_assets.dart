// Generates every IDSnap launcher icon and splash image from one vector
// description of the brand mark (viewfinder brackets, "ID", teal node), so
// Android and iOS stay identical.
//
// Run from apps/scanner:   dart run tool/generate_brand_assets.dart
//
// Source artwork: assets/brand/idsnap_mark.svg (same geometry, editable in
// any vector tool). If a designer replaces the mark, either update the
// geometry below or export PNGs at the sizes written in main().
//
// Not generated here (kept as supplied): the Android colour launcher icons
// (mipmap-*/ic_launcher*.png, drawable/ic_launcher_foreground.png).
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Brand colours from packages/design_system (DsColors).
const _blue = (0x24, 0x57, 0xD6); // blue600 — brand primary
const _teal = (0x0E, 0x8A, 0x7E); // teal600
const _white = (0xFF, 0xFF, 0xFF);

/// Paint of one mark sample: 0 = nothing, 1 = bracket/letters, 2 = node.
int _markSample(double x, double y) {
  // All coordinates in a 1024 × 1024 design space.
  // Node: teal ring at (714, 714), outer r 50, hole r 24.
  final dn = math.sqrt(math.pow(x - 714, 2) + math.pow(y - 714, 2));
  if (dn <= 50) return dn <= 24 ? 3 : 2; // 3 = ring hole
  // Brackets: fold into the top-left quadrant (they are symmetric).
  final fx = math.min(x, 1024 - x);
  final fy = math.min(y, 1024 - y);
  if (_bracketDistance(fx, fy) <= 38) return 1;
  // "I"
  if (x >= 320 && x <= 390 && y >= 356 && y <= 660) return 1;
  // "D": outer = stem + half-ellipse bowl, minus the inner counter.
  if (_inD(x, y, 450, 560, 144, 152) && !_inD(x, y, 520, 560, 74, 82)) {
    return 1;
  }
  return 0;
}

/// Distance from (x, y) to the top-left bracket centreline: a vertical arm
/// (148, 332)→(148, 258), a quarter arc (centre 258, r 110) and a horizontal
/// arm (258, 148)→(332, 148).
double _bracketDistance(double x, double y) {
  const c = 258.0;
  const r = 110.0;
  const edge = 148.0;
  const end = 332.0;
  var d = double.infinity;
  // Vertical arm.
  final vy = y.clamp(c, end);
  d = math.min(d, math.sqrt(math.pow(x - edge, 2) + math.pow(y - vy, 2)));
  // Horizontal arm.
  final hx = x.clamp(c, end);
  d = math.min(d, math.sqrt(math.pow(x - hx, 2) + math.pow(y - edge, 2)));
  // Arc (only in its own quadrant).
  if (x <= c && y <= c) {
    final len = math.sqrt(math.pow(x - c, 2) + math.pow(y - c, 2));
    d = math.min(d, (len - r).abs());
  }
  return d;
}

/// D-shaped region: a rectangle from [left] to [cx] plus a half ellipse
/// centred at (cx, 508), vertically 508 ± [ry].
bool _inD(double x, double y, double left, double cx, double rx, double ry) {
  const cy = 508.0;
  if (y < cy - ry || y > cy + ry || x < left) return false;
  if (x <= cx) return true;
  final nx = (x - cx) / rx;
  final ny = (y - cy) / ry;
  return nx * nx + ny * ny <= 1;
}

typedef Rgb = (int, int, int);

/// Renders the mark onto a [size]² canvas. The 1024 design space is scaled
/// to [markFraction] of the canvas and centred. A null [background] gives a
/// transparent canvas.
img.Image render(
  int size, {
  Rgb? background,
  Rgb fg = _blue,
  Rgb node = _teal,
  double markFraction = 1,
  bool alpha = true,
}) {
  final image = img.Image(
    width: size,
    height: size,
    numChannels: alpha ? 4 : 3,
  );
  const ss = 4; // 4 × 4 supersampling
  final scale = 1024 / (size * markFraction);
  final offset = (size - size * markFraction) / 2;
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var a = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final x = (px + (sx + 0.5) / ss - offset) * scale;
          final y = (py + (sy + 0.5) / ss - offset) * scale;
          final paint = _markSample(x, y);
          // 3 (the node's hole) and 0 show the background.
          final c = switch (paint) {
            1 => fg,
            2 => node,
            _ => background,
          };
          if (c == null) continue;
          r += c.$1;
          g += c.$2;
          b += c.$3;
          a += 1;
        }
      }
      const n = ss * ss;
      if (a == 0) {
        image.setPixelRgba(px, py, 0, 0, 0, 0);
        continue;
      }
      // Colour is the average of covered samples; alpha is the coverage.
      image.setPixelRgba(
        px,
        py,
        (r / a).round(),
        (g / a).round(),
        (b / a).round(),
        (a / n * 255).round(),
      );
    }
  }
  return image;
}

void _write(String path, img.Image image) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image, level: 9));
  stdout.writeln('wrote $path (${image.width}×${image.height})');
}

void main() {
  const res = 'android/app/src/main/res';
  const ios = 'ios/Runner/Assets.xcassets';

  // Master artwork (store listing size and a 1024 px master).
  _write(
    'assets/brand/idsnap_icon_1024.png',
    render(1024, background: _white, markFraction: 0.98, alpha: false),
  );

  // Android 13+ themed icon: monochrome layer, 108 dp canvas at xxxhdpi
  // (432 px), mark inside the 66 dp safe zone like the colour foreground.
  _write(
    '$res/drawable/ic_launcher_monochrome.png',
    render(432, fg: _white, node: _white, markFraction: 0.78),
  );

  // Android 12+ splash icon: 288 dp canvas (xxxhdpi = 1152 px), mark kept
  // inside the central 192 dp circle. White on the brand blue background.
  _write(
    '$res/drawable-xxxhdpi/splash_icon.png',
    render(1152, fg: _white, node: _white, markFraction: 0.44),
  );
  // Pre-12 launch_background bitmap: same mark, 120 dp at xxxhdpi.
  _write(
    '$res/drawable-xxxhdpi/splash_logo.png',
    render(480, fg: _white, node: _white),
  );

  // iOS AppIcon: full-bleed white, no alpha (App Store rejects alpha on the
  // 1024 marketing icon); iOS applies its own corner mask.
  const iconSizes = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  for (final e in iconSizes.entries) {
    _write(
      '$ios/AppIcon.appiconset/${e.key}',
      render(e.value, background: _white, markFraction: 0.98, alpha: false),
    );
  }

  // iOS launch screen logo: 120 pt, white on the brand blue (set in
  // LaunchScreen.storyboard).
  for (final (name, px) in [
    ('LaunchImage.png', 120),
    ('LaunchImage@2x.png', 240),
    ('LaunchImage@3x.png', 360),
  ]) {
    _write(
      '$ios/LaunchImage.imageset/$name',
      render(px, fg: _white, node: _white),
    );
  }
}
