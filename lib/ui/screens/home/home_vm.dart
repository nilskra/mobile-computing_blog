import 'dart:async';

import 'package:computing_blog/core/homestate.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/repository/blog_repository.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../../../domain/models/blog.dart';

@injectable
class HomeViewModel extends ChangeNotifier {
  HomeViewModel(this._repo) {
    state = HomeLoading();

    _blogSub = _repo.blogStream.listen(
      (blogs) {
        if (_isDisposed) return;

        state = HomeData(blogs);
        notifyListeners();
      },
      onError: (e) {
        if (_isDisposed) return;

        state = HomeError(e.toString());
        notifyListeners();
      },
    );

    // initialer Load
    _repo.getBlogPosts();
  }

  final BlogRepository _repo;

  late final StreamSubscription<List<Blog>> _blogSub;

  HomeState state = HomeLoading();
  bool _isDisposed = false;

  Stream<List<Blog>> get blogsStream => _repo.blogStream;

  bool isLoading = false;
  String? errorMessage;
  get _timer => null;

  @override
  void dispose() {
    _timer?.cancel();
    _blogSub.cancel();
    _isDisposed = true;
    super.dispose();
  }

  Future<void> fetch() async {
    state = HomeLoading();
    notifyListeners();

    await _repo.getBlogPosts();
  }

  Future<void> toggleLike(Blog blog) async {
  // optional: kleine UX-Optimierung (optimistisches Update)
  final currentState = state;
  if (currentState is HomeData) {
    // wir lassen die echte Wahrheit dann vom Backend/Stream kommen
    notifyListeners();
  }

  // Home nutzt aktuell fetch/state statt Stream-Listener -> nach Like neu laden
  await fetch();
}

}
