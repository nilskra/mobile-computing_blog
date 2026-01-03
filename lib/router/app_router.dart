import 'package:computing_blog/di/get_it_setup.dart';
import 'package:computing_blog/ui/screens/edit_blog/edit_blog_screen.dart';
import 'package:computing_blog/ui/screens/edit_blog/edit_blog_vm.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../ui/screens/scaffold_with_nav_bar.dart';
import '../ui/screens/home/home_screen.dart';
import '../ui/screens/home/home_vm.dart';
import '../ui/screens/create_blog/create_blog_screen.dart';
import '../ui/screens/create_blog/create_blog_vm.dart';
import '../ui/screens/blog_detail/blog_detail_screen.dart';
import '../ui/screens/blog_detail/blog_detail_vm.dart';
import '../models/blog.dart';
import 'app_routes.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return ScaffoldWithNavBar(child: child);
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) => NoTransitionPage(
            child: ChangeNotifierProvider<HomeViewModel>(
              create: (_) => getIt<HomeViewModel>(),
              child: const HomePage(),
            ),
          ),
          routes: [
            GoRoute(
              path: AppRoutes.blogDetail,
              pageBuilder: (context, state) {
                final blog = state.extra as Blog;
                return NoTransitionPage(
                  child: ChangeNotifierProvider(
                    create: (_) => getIt<BlogDetailViewModel>(param1: blog),
                    child: BlogDetailScreen(blog: blog),
                  ),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.editBlog,
              pageBuilder: (context, state) {
                final blog = state.extra as Blog;
                return NoTransitionPage(
                  child: ChangeNotifierProvider(
                    create: (_) => getIt<EditBlogViewModel>(param1: blog),
                    child: EditBlogScreen(blog: blog),
                  ),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.create,
          pageBuilder: (context, state) => NoTransitionPage(
            child: ChangeNotifierProvider(
              create: (_) => getIt<CreateBlogViewModel>(),
              child: const CreateBlogScreen(),
            ),
          ),
        ),
      ],
    ),
  ],
);
