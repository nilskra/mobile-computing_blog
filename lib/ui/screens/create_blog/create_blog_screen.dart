import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'create_blog_vm.dart';

class CreateBlogScreen extends StatelessWidget {
  const CreateBlogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CreateBlogViewModel>();

    return Scaffold(
      appBar: AppBar(title: const Text("New Blog")),
      body: Builder(
        builder: (context) {
          switch (viewModel.pageState) {
            case CreateBlogPageState.loading:
              return const Center(child: CircularProgressIndicator());
            case CreateBlogPageState.done:
              return Center(child: Text("Blog '${viewModel.title}' created!"));
            case CreateBlogPageState.editing:
              return Form(
                key: viewModel.formKey,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ListView(
                    children: [
                      const SizedBox(height: 20),
                      TextFormField(
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
