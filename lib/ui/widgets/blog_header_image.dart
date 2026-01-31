import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:computing_blog/ui/widgets/blog_image_chache_manager.dart';
import 'package:flutter/material.dart';

class BlogHeaderImage extends StatelessWidget {
  const BlogHeaderImage({super.key, required this.url, this.base64});

  final String url;
  final String? base64;
  
  @override
  Widget build(BuildContext context) {
    final b64 = base64;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: (b64 != null && b64.isNotEmpty)
          ? Image.memory(
              base64Decode(b64),
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => const SizedBox(
                height: 180,
                child: Center(child: Icon(Icons.broken_image)),
              ),
            )
          : CachedNetworkImage(
              imageUrl: url,
              cacheManager: BlogImageCacheManager(),
              fit: BoxFit.cover,
              placeholder: (context, _) => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, _, __) => const SizedBox(
                height: 180,
                child: Center(child: Icon(Icons.broken_image)),
              ),
            ),
    );
  }
}