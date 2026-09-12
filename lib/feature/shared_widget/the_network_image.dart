import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      // `LayoutBuilder` because the call sites pass `width: double.infinity`:
      // the only place the real slot width is known is here, after layout.
      child: LayoutBuilder(
        builder: (context, constraints) => CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: _decodeWidth(context, constraints),
          placeholder: (context, _) => Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(width: width, height: height, color: Colors.white),
          ),
          errorWidget: (context, _, __) => Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        ),
      ),
    );
  }

  /// Physical pixels to decode to, or null to leave the image at its served
  /// size.
  ///
  /// The API serves every image at 1600x1200 regardless of where it is shown.
  /// Flutter reported the cost directly with `debugInvertOversizedImages`:
  /// "display size of 1168x560 but a decode size of 1600x1200, which uses an
  /// additional 6593KB" — 10,000 KB held against 3,406 KB needed, on a feed
  /// card. `ImageCache` defaults to 100 MB, so at 10 MB apiece it holds ten
  /// images and a 122-deal feed evicts and re-decodes continuously; the worst
  /// raster frame measured spent 73.16 ms in `UploadTextureToPrivate`.
  ///
  /// Only the width is constrained. `ResizeImage` preserves the aspect ratio
  /// from a single dimension, and constraining both would stretch the image.
  /// That is safe while the box is wider than the source's 4:3 — true of all
  /// three call sites — because `BoxFit.cover` is then bound by width. For a
  /// box taller than it is wide, cover would be bound by height instead and a
  /// width hint would make it decode too small and blur, so the hint is
  /// withheld rather than guessed.
  int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final slotWidth = constraints.maxWidth;
    if (!slotWidth.isFinite || slotWidth <= 0) return null;
    final slotHeight = constraints.maxHeight;
    if (slotHeight.isFinite && slotHeight > slotWidth) return null;
    return (slotWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
  }
}
