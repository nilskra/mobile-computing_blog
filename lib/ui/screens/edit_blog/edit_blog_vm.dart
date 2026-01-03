import 'package:computing_blog/data/blog_repository.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../../../models/blog.dart';

enum EditBlogPageState { loading, editing, done }

@injectable
class EditBlogViewModel extends ChangeNotifier {
  EditBlogViewModel(this._repo, @factoryParam this.blog);
  final BlogRepository _repo;
  final Blog blog;

  final formKey = GlobalKey<FormState>();
  
  EditBlogPageState _pageState = EditBlogPageState.editing;
  String _title = "";
  String _content = "";

  EditBlogPageState get pageState => _pageState;
  String get title => _title;
  String get content => _content;

void setTitle(String value) {
    _title = value;
  }

  void setContent(String value) {
    _content = value;
  }

  String? validateTitle(String? value) {
    if (value == null || value.length < 4) {
      return "Please enter title with 4 or more characters";
    }
    return null;
  }

  String? validateContent(String? value) {
    if (value == null || value.length < 10) {
      return "Please enter content with 10 or more characters";
    }
    return null;
  }

  Future<void> save() async {
    if (formKey.currentState?.validate() ?? false) {
      formKey.currentState?.save();
      await updateBlog();
    }
  }

  Future<void> updateBlog() async {
    _pageState = EditBlogPageState.loading;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    await _repo.updateBlogPost( blog.id,
      blogId: blog.id, 
      title: _title, 
      content: _content
    );

    _pageState = EditBlogPageState.done;
    notifyListeners();
  }

}