import 'package:computing_blog/core/homestate.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../router/app_routes.dart';
import 'home_vm.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          appBar: AppBar(title: const Text("Blog")),
          body: switch (vm.state) {
            HomeLoading() => const Center(child: CircularProgressIndicator()),

            HomeError(message: var msg) => Center(child: Text(msg)),

            HomeData(blogs: var blogs) => RefreshIndicator(
              onRefresh: vm.fetch,
              child: BlogList(blogs),
            ),

            HomeInitial() => const SizedBox(),
          },
        );
      },
    );
  }
}

class BlogList extends StatelessWidget {
  final List<Blog> blogs;
  const BlogList(this.blogs, {super.key});

  @override
  Widget build(BuildContext context) {
    if (blogs.isEmpty) {
      return const Center(child: Text("Keine Blogs vorhanden"));
    }

    return ListView.builder(
      itemCount: blogs.length,
      itemBuilder: (context, index) => BlogWidget(blog: blogs[index]),
    );
  }
}

class BlogWidget extends StatelessWidget {
  const BlogWidget({super.key, required this.blog});

  final Blog blog;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          context.go(AppRoutes.toBlogDetail(blog.title), extra: blog);
        },
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (blog.headerImageUrl != null)
                  Text("ich bin hier!)")
                  
                else
                  drawImage(
                    'https://picsum.photos/seed/${blog.id}/500',
                  ), // Es soll random Bild angezeigt werden
                SizedBox(height: 5),
                Text(
                  blog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  blog.contentPreview ?? blog.content ?? "",
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      blog.publishedAt.toIso8601String(),
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Like',
                          onPressed: () =>
                              context.read<HomeViewModel>().toggleLike(blog),
                          icon: Icon(
                            blog.isLikedByMe
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                        ),
                        Text('${blog.likes}'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget drawImage(String imageUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 👈 links!
      children: [
        SizedBox(
          width: 300,
          height: 200,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.broken_image_outlined,
                size: 50,
                color: Colors.grey,
              );
            },
          ),
        ),
        const SizedBox(height: 5),
      ],
    );
  }
}
