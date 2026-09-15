import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image/image.dart' as img;

class PictureSetupPage extends StatefulWidget {
  final String wallId;

  const PictureSetupPage({super.key, required this.wallId});

  @override
  State<PictureSetupPage> createState() => _PictureSetupPageState();
}

class _PictureSetupPageState extends State<PictureSetupPage> {
  bool _loading = true;
  bool _processingPreview = false;
  bool _savingImage = false;

  String? _error;

  final ImagePicker _picker = ImagePicker();

  // Full-quality source image.
  File? _sourceImage;

  // Reduced-size source used for fast adjustments.
  File? _previewSourceImage;

  // What is currently shown on screen.
  File? _currentPreviewImage;

  double _brightness = 1.0;
  double _contrast = 1.0;

  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentImage();
  }

  // ============================================================
  // LOCAL FILE
  // ============================================================

  Future<File> _getLocalWallFile(String wallId, String filename) async {
    final dir = await getApplicationDocumentsDirectory();

    final wallDir = Directory('${dir.path}/walls/$wallId');

    if (!await wallDir.exists()) {
      await wallDir.create(recursive: true);
    }

    return File('${wallDir.path}/$filename');
  }

  // ============================================================
  // LOAD CURRENT WALL.PNG
  // ============================================================

  Future<void> _loadCurrentImage() async {
    try {
      final file = await _getLocalWallFile(widget.wallId, "wall.png");

      if (await file.exists()) {
        _sourceImage = file;

        await _createPreviewSource(file);
      }

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ============================================================
  // TAKE PHOTO
  // ============================================================

  Future<void> _takePhoto() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );

      if (picked == null) return;

      final file = File(picked.path);

      await _setNewSourceImage(file);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not take photo:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // CHOOSE PHOTO FROM PHONE
  // ============================================================

  Future<void> _choosePhoto() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (picked == null) return;

      final file = File(picked.path);

      await _setNewSourceImage(file);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not choose photo:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // SET NEW SOURCE IMAGE
  // ============================================================

  Future<void> _setNewSourceImage(File file) async {
    if (!mounted) return;

    setState(() {
      _processingPreview = true;

      _sourceImage = file;

      // Don't keep showing the previous wall photo
      // while the new preview is being generated.
      _currentPreviewImage = null;
      _previewSourceImage = null;

      _brightness = 1.0;
      _contrast = 1.0;

      _error = null;
    });

    try {
      await _createPreviewSource(file);
    } finally {
      if (!mounted) return;

      setState(() {
        _processingPreview = false;
      });
    }
  }

  // ============================================================
  // CREATE REDUCED-SIZE PREVIEW SOURCE
  // ============================================================

  Future<void> _createPreviewSource(File source) async {
    final tempDir = await getTemporaryDirectory();

    // Every new camera/gallery/crop image gets
    // a different preview filename.
    final generation = ++_previewGeneration;

    final previewFile = File(
      '${tempDir.path}/'
      'dtb_${widget.wallId}_preview_source_$generation.jpg',
    );

    final resultPath = await compute(_buildPreviewImageTask, {
      'sourcePath': source.path,
      'outputPath': previewFile.path,
    });

    final resultFile = File(resultPath);

    if (!mounted) return;

    setState(() {
      _previewSourceImage = resultFile;
      _currentPreviewImage = resultFile;
    });
  }

  // ============================================================
  // CROP / ROTATE / STRAIGHTEN
  // ============================================================

  Future<void> _cropImage() async {
    final source = _sourceImage;

    if (source == null) {
      return;
    }

    try {
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: source.path,
        compressFormat: ImageCompressFormat.png,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: "Crop Wall Picture",
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(title: "Crop Wall Picture"),
        ],
      );

      if (cropped == null) {
        return;
      }

      final croppedFile = File(cropped.path);

      if (!mounted) return;

      setState(() {
        _processingPreview = true;

        _sourceImage = croppedFile;

        _brightness = 1.0;
        _contrast = 1.0;
      });

      await _createPreviewSource(croppedFile);

      if (!mounted) return;

      setState(() {
        _processingPreview = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not crop picture:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // UPDATE PREVIEW
  // ============================================================

  Future<void> _applyPreviewAdjustments() async {
    final source = _previewSourceImage;

    if (source == null) {
      return;
    }

    final generation = ++_previewGeneration;

    if (!mounted) return;

    setState(() {
      _processingPreview = true;
    });

    try {
      final tempDir = await getTemporaryDirectory();

      final adjustedFile = File(
        '${tempDir.path}/'
        'dtb_${widget.wallId}_preview_adjusted_$generation.png',
      );

      final resultPath = await compute(_processImageTask, {
        'sourcePath': source.path,
        'outputPath': adjustedFile.path,
        'brightness': _brightness,
        'contrast': _contrast,
        'maxDimension': 1200,
      });

      if (!mounted) return;

      // Ignore an older result if the user
      // has moved the slider again meanwhile.
      if (generation != _previewGeneration) {
        return;
      }

      setState(() {
        _currentPreviewImage = File(resultPath);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not update preview:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;

      if (generation == _previewGeneration) {
        setState(() {
          _processingPreview = false;
        });
      }
    }
  }

  // ============================================================
  // RESET ADJUSTMENTS
  // ============================================================

  void _resetAdjustments() {
    final source = _previewSourceImage;

    if (source == null) return;

    setState(() {
      _brightness = 1.0;
      _contrast = 1.0;

      _currentPreviewImage = source;
    });
  }

  // ============================================================
  // SAVE FINAL FULL-QUALITY IMAGE
  // ============================================================

  Future<void> _usePicture() async {
    final source = _sourceImage;

    if (source == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _savingImage = true;
    });

    try {
      final destination = await _getLocalWallFile(widget.wallId, "wall.png");

      await compute(_processImageTask, {
        'sourcePath': source.path,
        'outputPath': destination.path,
        'brightness': _brightness,
        'contrast': _contrast,
        'maxDimension': null,
      });

      if (!mounted) return;

      setState(() {
        _savingImage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Wall picture saved locally."),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _savingImage = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not save wall picture:\n$e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // DISPLAY HELPERS
  // ============================================================

  String _adjustmentLabel(double value) {
    final percent = ((value - 1.0) * 100).round();

    if (percent == 0) {
      return "Normal";
    }

    if (percent > 0) {
      return "+$percent%";
    }

    return "$percent%";
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Wall Picture")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              widget.wallId,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            const Text(
              "Choose a clear picture of the complete wall. "
              "Try to photograph the board as straight-on as possible. "
              "This picture will be used when mapping each hold to its LED.",
            ),

            const SizedBox(height: 20),

            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),

            // ==================================================
            // PREVIEW
            // ==================================================
            if (_currentPreviewImage != null)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          constraints: const BoxConstraints(
                            minHeight: 220,
                            maxHeight: 500,
                          ),
                          width: double.infinity,
                          color: Colors.black,
                          child: Image.file(
                            _currentPreviewImage!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            key: ValueKey(_currentPreviewImage!.path),
                          ),
                        ),

                        if (_processingPreview)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black38,
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text(
                                    "Updating preview...",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text("Wall picture preview"),
                    ),
                  ],
                ),
              )
            else
              const Card(
                child: SizedBox(
                  height: 240,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_not_supported_outlined, size: 48),
                        SizedBox(height: 12),
                        Text("No wall picture found"),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // ==================================================
            // PHOTO SOURCE
            // ==================================================
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _processingPreview || _savingImage
                    ? null
                    : _takePhoto,
                icon: const Icon(Icons.photo_camera),
                label: const Text("Take Photo"),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _processingPreview || _savingImage
                    ? null
                    : _choosePhoto,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text("Choose Photo From Phone"),
              ),
            ),

            if (_sourceImage != null) ...[
              const SizedBox(height: 24),

              Text(
                "Adjust Picture",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 12),

              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _processingPreview || _savingImage
                      ? null
                      : _cropImage,
                  icon: const Icon(Icons.crop),
                  label: const Text("Crop / Rotate / Straighten"),
                ),
              ),

              const SizedBox(height: 20),

              // ================================================
              // BRIGHTNESS
              // ================================================
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Brightness",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(_adjustmentLabel(_brightness)),
                ],
              ),

              Slider(
                value: _brightness,
                min: 0.70,
                max: 1.30,
                divisions: 60,
                label: _adjustmentLabel(_brightness),
                onChanged: _savingImage
                    ? null
                    : (value) {
                        setState(() {
                          _brightness = value;
                        });
                      },
                onChangeEnd: _savingImage
                    ? null
                    : (_) {
                        _applyPreviewAdjustments();
                      },
              ),

              // ================================================
              // CONTRAST
              // ================================================
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Contrast",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(_adjustmentLabel(_contrast)),
                ],
              ),

              Slider(
                value: _contrast,
                min: 0.70,
                max: 1.30,
                divisions: 60,
                label: _adjustmentLabel(_contrast),
                onChanged: _savingImage
                    ? null
                    : (value) {
                        setState(() {
                          _contrast = value;
                        });
                      },
                onChangeEnd: _savingImage
                    ? null
                    : (_) {
                        _applyPreviewAdjustments();
                      },
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _processingPreview || _savingImage
                      ? null
                      : _resetAdjustments,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reset Brightness & Contrast"),
                ),
              ),
            ],

            const SizedBox(height: 28),

            // ==================================================
            // SAVE
            // ==================================================
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    _sourceImage == null || _processingPreview || _savingImage
                    ? null
                    : _usePicture,
                icon: _savingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _savingImage
                      ? "Saving Full Quality Picture..."
                      : "Use This Picture",
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BACKGROUND IMAGE PROCESSING HELPERS
// ============================================================

String _buildPreviewImageTask(Map<String, dynamic> args) {
  final sourcePath = args['sourcePath'] as String;

  final outputPath = args['outputPath'] as String;

  final bytes = File(sourcePath).readAsBytesSync();

  img.Image? image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception("Could not decode image.");
  }

  const maxDimension = 1200;

  if (image.width > maxDimension || image.height > maxDimension) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxDimension);
    } else {
      image = img.copyResize(image, height: maxDimension);
    }
  }

  File(
    outputPath,
  ).writeAsBytesSync(img.encodeJpg(image, quality: 90), flush: true);

  return outputPath;
}

String _processImageTask(Map<String, dynamic> args) {
  final sourcePath = args['sourcePath'] as String;

  final outputPath = args['outputPath'] as String;

  final brightness = (args['brightness'] as num).toDouble();

  final contrast = (args['contrast'] as num).toDouble();

  final maxDimension = args['maxDimension'] as int?;

  final bytes = File(sourcePath).readAsBytesSync();

  img.Image? image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception("Could not decode image.");
  }

  if (maxDimension != null &&
      (image.width > maxDimension || image.height > maxDimension)) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxDimension);
    } else {
      image = img.copyResize(image, height: maxDimension);
    }
  }

  image = img.adjustColor(image, brightness: brightness, contrast: contrast);

  if (outputPath.toLowerCase().endsWith('.png')) {
    File(outputPath).writeAsBytesSync(img.encodePng(image), flush: true);
  } else {
    File(
      outputPath,
    ).writeAsBytesSync(img.encodeJpg(image, quality: 92), flush: true);
  }

  return outputPath;
}
