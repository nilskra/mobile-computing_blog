class AppRoutes {
  // Top-Level Routes
  static const String home = '/';
  static const String create = '/create';

  // Sub-Routes (relativ zur Parent-Route)
  static const String blogDetail = 'blog/:id';
  static const String editBlog = 'edit/:id';

  // Helper-Methoden zum Generieren konkreter Pfade
  static String toBlogDetail(String id) => '/blog/$id';
  static String toEditBlog(String id) => '/edit/$id';
}
