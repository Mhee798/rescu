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
      child: LayoutBuilder(builder: (context, constraints) {
        final (decodeWidth, decodeHeight) = _decodeSize(context, constraints);
        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: decodeWidth,
          memCacheHeight: decodeHeight,
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
        );
      }),
    );
  }

  /// Physical pixels to decode to, or null to leave the image at its served
  /// size. Exactly one of the two is ever set.
  ///
  /// The API serves every image at 1600×1200 (`fake_api_service.dart:267`),
  /// so the decode size is otherwise fixed no matter how small the slot is.
  /// Flutter reported the cost directly with `debugInvertOversizedImages`:
  /// "display size of 1168×560 but a decode size of 1600×1200, which uses an
  /// additional 6593KB" — 10,000 KB held against 3,406 KB needed, on a feed
  /// card. Measured on device, `ImageCache` held 13 images before this and 36
  /// after, at its 100 MB default.
  ///
  /// Only one dimension may be hinted: `ResizeImage` keeps the aspect ratio
  /// from a single value and would stretch the image if given both. Which one
  /// is not a free choice — `BoxFit.cover` is bound by whichever dimension is
  /// proportionally larger, and hinting the *other* one decodes too small and
  /// blurs. So the box's aspect is compared against the source's: wider than
  /// 4:3 and cover is width-bound, narrower and it is height-bound. The square
  /// 64×64 thumbnails in the cart and orders screens are the case that needs
  /// this; a width-only rule blurred them by upscaling 1.33×.
  ///
  /// Both dimensions are read from this widget's own fields first and from the
  /// incoming constraints only as a fallback. The constraints alone are not
  /// enough: the feed card and the flash rail both sit in a `Column`, so the
  /// height reaching the `LayoutBuilder` is infinite and their real height
  /// exists only as `this.height`.
  static const double _sourceAspectRatio = 4 / 3;

  (int?, int?) _decodeSize(BuildContext context, BoxConstraints constraints) {
    final slotWidth = _finite(width) ?? constraints.maxWidth;
    final slotHeight = _finite(height) ?? constraints.maxHeight;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    if (slotWidth.isFinite && slotWidth > 0) {
      final widthBound = !slotHeight.isFinite ||
          slotHeight <= 0 ||
          slotWidth / slotHeight >= _sourceAspectRatio;
      if (widthBound) return ((slotWidth * dpr).ceil(), null);
    }
    if (slotHeight.isFinite && slotHeight > 0) {
      return (null, (slotHeight * dpr).ceil());
    }
    return (null, null);
  }

  static double? _finite(double? value) =>
      (value != null && value.isFinite) ? value : null;
}
