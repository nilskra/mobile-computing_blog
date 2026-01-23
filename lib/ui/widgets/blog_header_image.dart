import 'package:cached_network_image/cached_network_image.dart';
import 'package:computing_blog/ui/widgets/blog_image_chache_manager.dart';
import 'package:flutter/material.dart';

class BlogHeaderImage extends StatelessWidget {
  const BlogHeaderImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheManager: BlogImageCacheManager(),
        fit: BoxFit.cover,
        placeholder: (context, _) =>
            const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
        errorWidget: (context, _, __) =>
            const SizedBox(height: 180, child: Center(child: Icon(Icons.broken_image))),
      ),
    );
  }
}
