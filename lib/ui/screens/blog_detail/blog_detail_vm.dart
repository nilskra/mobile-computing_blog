import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import '../../../models/blog.dart';

@injectable
class BlogDetailViewModel extends ChangeNotifier {
  BlogDetailViewModel(@factoryParam this.blog);
  final Blog blog;

}
