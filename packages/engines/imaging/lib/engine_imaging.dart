/// Pure-Dart document imaging: page detection, perspective correction,
/// enhancement filters, cropping and compression. Web-safe (no dart:io).
library;

export 'src/detect/detector.dart' show detectPage;
export 'src/geometry/homography.dart' show Homography;
export 'src/imaging_engine.dart';
export 'src/raster.dart'
    show
        DecodedRaster,
        RasterDecoder,
        RasterSource,
        Rgb,
        decodeRgb,
        encodeJpeg,
        encodePng;
