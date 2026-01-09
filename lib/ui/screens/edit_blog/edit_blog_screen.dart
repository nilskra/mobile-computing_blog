import 'package:computing_blog/router/app_routes.dart';
import 'package:computing_blog/ui/screens/edit_blog/edit_blog_vm.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../domain/models/blog.dart';

class EditBlogScreen extends StatelessWidget {
  final Blog blog;

  const EditBlogScreen({super.key, required this.blog});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EditBlogViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Blog")),
      body: Builder(
        builder: (context) {
          switch (viewModel.pageState) {
            case EditBlogPageState.loading:
              return const Center(child: CircularProgressIndicator());
            case EditBlogPageState.done:
              return Center(child: Text("Blog '${viewModel.title}' edited!"));
            case EditBlogPageState.editing:
              return Form(
                key: viewModel.formKey,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListView(
                    children: [
                      const SizedBox(height: 20),
                      TextFormField(
                        initialValue: blog.title,
                        decoration: const InputDecoration(
                          labelText: "Title",
                          border: OutlineInputBorder(),
                        ),
                        validator: viewModel.validateTitle,
                        onSaved: (value) => viewModel.setTitle(value!),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        maxLines: 10,
                        initialValue: blog.content,
                        decoration: const InputDecoration(
                          labelText: "Content",
                          border: OutlineInputBorder(),
                        ),
                        validator: viewModel.validateContent,
                        onSaved: (value) => viewModel.setContent(value!),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () async {
                          // Hide keyboard
                          FocusScope.of(context).unfocus();
                          await viewModel.save();
                          context.go(AppRoutes.home);
                        },
                        child: const Text("Save"),
                      ),
                      const SizedBox(height: 8.0),
                    ],
                  ),
                ),
              );
          }
        },
      ),
    );
  }
}
