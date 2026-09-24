import 'dart:typed_data';

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_lab/src/compress_tab.dart';
import 'package:docscan_lab/src/imaging_tab.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Picks one image and returns its bytes, or null when cancelled.
typedef ImageSource = Future<Uint8List?> Function();

Future<Uint8List?> pickImageBytes() async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  return await files.first.readAsBytes();
}

/// Engine Lab: a developer tool for exercising the imaging engine on real
/// photos without the phone camera. Runs on web and Android.
class LabApp extends StatefulWidget {
  const LabApp({super.key, this.processor, this.source});

  final ImageProcessor? processor;
  final ImageSource? source;

  @override
  State<LabApp> createState() => _LabAppState();
}

class _LabAppState extends State<LabApp> {
  ThemeMode _mode = ThemeMode.system;
  Uint8List? _image;

  late final ImageProcessor _processor =
      widget.processor ?? const ImagingEngine();

  Future<void> _pick() async {
    final bytes = await (widget.source ?? pickImageBytes)();
    if (bytes != null && mounted) setState(() => _image = bytes);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DocScan Engine Lab',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: _mode,
    home: DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Engine Lab'),
            actions: [
              IconButton(
                tooltip: 'Toggle light / dark',
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                ),
                onPressed: () => setState(
                  () => _mode = Theme.of(context).brightness == Brightness.dark
                      ? ThemeMode.light
                      : ThemeMode.dark,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.x2),
                child: FilledButton.tonalIcon(
                  onPressed: _pick,
                  icon: const Icon(Icons.image_search_rounded),
                  label: const Text('Pick an image'),
                ),
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Detect & filters'),
                Tab(text: 'Crop & compress'),
              ],
            ),
          ),
          body: _image == null
              ? EmptyState(
                  icon: Icons.science_outlined,
                  title: 'Pick a document photo',
                  message:
                      'The lab runs page detection, perspective correction, every filter, '
                      'compression and passport cropping locally and reports timings.',
                  actionLabel: 'Pick an image',
                  onAction: _pick,
                )
              : TabBarView(
                  children: [
                    ImagingTab(
                      key: ObjectKey(_image),
                      image: _image!,
                      processor: _processor,
                    ),
                    CompressTab(
                      key: ObjectKey(_image),
                      image: _image!,
                      processor: _processor,
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
