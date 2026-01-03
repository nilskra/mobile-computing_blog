import 'package:computing_blog/models/blog.dart';

sealed class HomeState {}

class HomeInitial extends HomeState {}

class HomeLoading extends HomeState {}

class HomeData extends HomeState {
  final List<Blog> blogs;
  HomeData(this.blogs);
}

class HomeError extends HomeState {
  final String message;
  HomeError(this.message);
}