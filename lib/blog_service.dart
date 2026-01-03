
import 'package:computing_blog/models/blog.dart';
import 'package:uuid/uuid.dart';

List<Blog> blogs = [
  Blog(
    title: "Lorem ipsum",
    content: "Blabliblub",
    publishedAt: DateTime.now(), 
    id: Uuid().toString(),
  ),
  Blog(
    title: "Lorem ipsum",
    content: "Blabliblub",
    publishedAt: DateTime.now(),
    id: Uuid().toString(),
  ),
  Blog(
    title: "Pause!!!!!!!!!!!!!!!!!!!!",
    content: "Blabliblub",
    publishedAt: DateTime.now(),
    id: Uuid().toString(),
  ),
];

class BlogService {
  List<Blog> getBlogs() => blogs;
}
