import 'package:computing_blog/core/homestate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/blog.dart';
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
                Text(
                  blog.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(blog.content),
                const SizedBox(height: 8.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      blog.publishedDateString,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
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
}
