// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../data/api/blog_api.dart' as _i228;
import '../data/repository/blog_repository.dart' as _i1047;
import '../domain/models/blog.dart' as _i778;
import '../local/blog_cache.dart' as _i560;
import '../local/pending_ops_store.dart' as _i717;
import '../local/sync_service.dart' as _i1024;
import '../ui/screens/blog_detail/blog_detail_vm.dart' as _i150;
import '../ui/screens/create_blog/create_blog_vm.dart' as _i131;
import '../ui/screens/edit_blog/edit_blog_vm.dart' as _i459;
import '../ui/screens/home/home_vm.dart' as _i1038;
import 'storage_module.dart' as _i371;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final storageModule = _$StorageModule();
    gh.lazySingleton<_i228.BlogApi>(() => _i228.BlogApi());
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => storageModule.secureStorage,
    );
    gh.lazySingleton<_i560.BlogCache>(() => _i560.BlogCache());
    gh.lazySingleton<_i717.PendingOpsStore>(() => _i717.PendingOpsStore());
    gh.factoryParam<_i150.BlogDetailViewModel, _i778.Blog, dynamic>(
      (blog, _) => _i150.BlogDetailViewModel(blog),
    );
    gh.lazySingleton<_i1024.SyncService>(
      () => _i1024.SyncService(
        gh<_i228.BlogApi>(),
        gh<_i717.PendingOpsStore>(),
        gh<_i560.BlogCache>(),
      ),
    );
    gh.lazySingleton<_i1047.BlogRepository>(
      () => _i1047.BlogRepository(
        gh<_i228.BlogApi>(),
        gh<_i560.BlogCache>(),
        gh<_i717.PendingOpsStore>(),
        gh<_i1024.SyncService>(),
      ),
    );
    gh.factory<_i131.CreateBlogViewModel>(
      () => _i131.CreateBlogViewModel(gh<_i1047.BlogRepository>()),
    );
    gh.factory<_i1038.HomeViewModel>(
      () => _i1038.HomeViewModel(gh<_i1047.BlogRepository>()),
    );
    gh.factoryParam<_i459.EditBlogViewModel, _i778.Blog, dynamic>(
      (blog, _) => _i459.EditBlogViewModel(gh<_i1047.BlogRepository>(), blog),
    );
    return this;
  }
}

class _$StorageModule extends _i371.StorageModule {}
