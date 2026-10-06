import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:feature_tools/src/kits/kit_screen.dart';
import 'package:feature_tools/src/kits/kits_hub_screen.dart';
import 'package:feature_tools/src/protect/protect_file_screen.dart';
import 'package:feature_tools/src/protect/remove_password_screen.dart';
import 'package:feature_tools/src/screens/compress_image_screen.dart';
import 'package:feature_tools/src/screens/compress_pdf_screen.dart';
import 'package:feature_tools/src/screens/convert_screen.dart';
import 'package:feature_tools/src/screens/images_to_pdf_screen.dart';
import 'package:feature_tools/src/screens/merge_screen.dart';
import 'package:feature_tools/src/screens/ocr_screen.dart';
import 'package:feature_tools/src/screens/organize_screen.dart';
import 'package:feature_tools/src/screens/pdf_to_images_screen.dart';
import 'package:feature_tools/src/screens/photo_crop_screen.dart';
import 'package:feature_tools/src/screens/resize_image_screen.dart';
import 'package:feature_tools/src/screens/split_screen.dart';
import 'package:feature_tools/src/signature/my_signature_screen.dart';
import 'package:feature_tools/src/signature/sign_pdf_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Tool routes, relative to `/tools`. Each covers the bottom navigation.
/// Every route accepts `?doc=<documentId>` to preselect a library file.
List<RouteBase> toolRoutes(GlobalKey<NavigatorState> rootKey) {
  String? doc(GoRouterState s) => s.uri.queryParameters['doc'];

  GoRoute route(ToolId id, Widget Function(String? docId) build) => GoRoute(
    path: id.path,
    parentNavigatorKey: rootKey,
    builder: (context, state) => build(doc(state)),
  );

  return [
    route(ToolId.ocr, (d) => OcrScreen(initialDocId: d)),
    route(ToolId.imagesToPdf, (d) => ImagesToPdfScreen(initialDocId: d)),
    route(ToolId.merge, (d) => MergeScreen(initialDocId: d)),
    route(ToolId.split, (d) => SplitScreen(initialDocId: d)),
    route(ToolId.organize, (d) => OrganizeScreen(initialDocId: d)),
    route(ToolId.compressPdf, (d) => CompressPdfScreen(initialDocId: d)),
    route(ToolId.pdfToImages, (d) => PdfToImagesScreen(initialDocId: d)),
    route(ToolId.compressImage, (d) => CompressImageScreen(initialDocId: d)),
    route(ToolId.photoCrop, (d) => PhotoCropScreen(initialDocId: d)),
    route(ToolId.resizeImage, (d) => ResizeImageScreen(initialDocId: d)),
    route(ToolId.signPdf, (d) => SignPdfScreen(initialDocId: d)),
    route(ToolId.mySignature, (_) => const MySignatureScreen()),
    route(ToolId.protectFile, (d) => ProtectFileScreen(initialDocId: d)),
    route(
      ToolId.removePdfPassword,
      (d) => RemovePdfPasswordScreen(initialDocId: d),
    ),
    GoRoute(
      path: ToolId.kits.path,
      parentNavigatorKey: rootKey,
      builder: (context, state) => const KitsHubScreen(),
      routes: [
        GoRoute(
          path: ':kitId',
          parentNavigatorKey: rootKey,
          builder: (context, state) =>
              KitScreen(kitId: state.pathParameters['kitId']!),
        ),
      ],
    ),
    GoRoute(
      path: ToolId.convert.path,
      parentNavigatorKey: rootKey,
      builder: (context, state) => ConvertListScreen(initialDocId: doc(state)),
      routes: [
        GoRoute(
          path: ':specId',
          parentNavigatorKey: rootKey,
          builder: (context, state) => ConvertScreen(
            specId: state.pathParameters['specId']!,
            initialDocId: doc(state),
          ),
        ),
      ],
    ),
  ];
}
