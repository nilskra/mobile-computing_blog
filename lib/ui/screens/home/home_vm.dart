import 'dart:async';

import 'package:computing_blog/core/homestate.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/repository/blog_repository.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../../../domain/models/blog.dart';

@injectable
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this._repo){
    _repo.getBlogPosts();
  }

  final BlogRepository _repo;

  HomeState state = HomeLoading();
  bool _isDisposed = false;

  Stream<List<Blog>> get blogsStream => _repo.blogStream;

  bool isLoading = false;
  String? errorMessage;
  get _timer => null;

  @override
  void dispose() {
    _timer?.cancel();
    _isDisposed = true;
    super.dispose();
  }

  Future<void> fetch() async {
    state = HomeLoading();
    notifyListeners();

    final result = await _repo.getBlogPosts();

    if (_isDisposed) return;

    switch (result) {
      case Success(data: var blogs):
        state = HomeData(blogs);
      case Failure(error: var e):
        state = HomeError(e.toString());
    }
    notifyListeners();
  }
}
