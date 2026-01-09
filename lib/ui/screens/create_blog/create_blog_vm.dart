import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../../../data/repository/blog_repository.dart';
import '../../../domain/models/blog.dart';
import 'package:uuid/uuid.dart';

enum CreateBlogPageState { loading, editing, done }

@injectable
class CreateBlogViewModel extends ChangeNotifier {
  CreateBlogViewModel(this._repo);
  final BlogRepository _repo;

  final formKey = GlobalKey<FormState>();
  CreateBlogPageState _pageState = CreateBlogPageState.editing;
  String _title = "";
  String _content = "";

  CreateBlogPageState get pageState => _pageState;
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
      await createBlog();
    }
  }

  Future<void> createBlog() async {
    _pageState = CreateBlogPageState.loading;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));
    await _repo.addBlogPost(
      Blog(title: _title, content: _content, publishedAt: DateTime.now(), id: Uuid().toString()),
    );

    _pageState = CreateBlogPageState.done;
    notifyListeners();
  }
}
