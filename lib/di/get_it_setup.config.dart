// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../data/api/blog_api.dart' as _i359;
import '../data/repository/blog_repository.dart' as _i168;
import '../domain/models/blog.dart' as _i600;
import '../ui/screens/blog_detail/blog_detail_vm.dart' as _i150;
import '../ui/screens/create_blog/create_blog_vm.dart' as _i131;
import '../ui/screens/edit_blog/edit_blog_vm.dart' as _i459;
import '../ui/screens/home/home_vm.dart' as _i1038;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    gh.lazySingleton<_i359.BlogApi>(() => _i359.BlogApi());
    gh.factoryParam<_i150.BlogDetailViewModel, _i600.Blog, dynamic>(
      (blog, _) => _i150.BlogDetailViewModel(blog),
    );
    gh.lazySingleton<_i168.BlogRepository>(
      () => _i168.BlogRepository(gh<_i359.BlogApi>()),
    );
    gh.factory<_i131.CreateBlogViewModel>(
      () => _i131.CreateBlogViewModel(gh<_i168.BlogRepository>()),
    );
    gh.factory<_i1038.HomeViewModel>(
      () => _i1038.HomeViewModel(gh<_i168.BlogRepository>()),
    );
    gh.factoryParam<_i459.EditBlogViewModel, _i600.Blog, dynamic>(
      (blog, _) => _i459.EditBlogViewModel(gh<_i168.BlogRepository>(), blog),
    );
    return this;
  }
}
