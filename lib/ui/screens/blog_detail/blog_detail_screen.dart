import 'package:computing_blog/ui/widgets/blog_header_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/models/blog.dart';
import '../../../router/app_routes.dart';

class BlogDetailScreen extends StatelessWidget {
  final Blog blog;

  const BlogDetailScreen({super.key, required this.blog});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blog Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${blog.publishedAt.day}.${blog.publishedAt.month}.${blog.publishedAt.year}",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (blog.headerImageUrl != null &&
                    blog.headerImageUrl!.isNotEmpty) ...[
                  BlogHeaderImage(url: blog.headerImageUrl!, base64: blog.headerImageBase64),
                  const SizedBox(height: 16),
                ],
                Text(
                  blog.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  blog.contentPreview ?? "",
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),

          Positioned(
            right: 16,
            top: 16,
            child: FloatingActionButton(
              onPressed: () {
                context.go(AppRoutes.toEditBlog(blog.title), extra: blog);
              },
              child: const Icon(Icons.edit),
            ),
          ),
        ],
      ),
    );
  }
}