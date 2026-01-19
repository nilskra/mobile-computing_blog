import 'package:computing_blog/core/logger.util.dart';
import 'package:computing_blog/data/repository/auth_repository.dart';
import 'package:computing_blog/di/get_it_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:global_configuration/global_configuration.dart';
import 'package:logger/logger.dart';

import 'router/app_router.dart';

import 'package:app_links/app_links.dart';

Future<void> main() async {
  Logger.level = Level.debug;
  WidgetsFlutterBinding.ensureInitialized();

  const flavor = String.fromEnvironment(
    'FLUTTER_APP_FLAVOR',
    defaultValue: 'development',
  );

  await GlobalConfiguration().loadFromAsset('app_settings.json');

  configureDependencies();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("Flutter Error: ${details.exception}");
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception); // Standard "Red Screen" im Debug
    }
    return const Center(
      child: Text(
        "Ein unerwarteter Fehler ist aufgetreten.",
        style: TextStyle(color: Colors.orange),
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    return true;
  };

  // 1. Auth Status prüfen (wartet nicht zwingend auf Ergebnis, kann async sein)
  await AuthRepository.instance.checkLoginStatus();

  // 2. Deep Links Setup
  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen((uri) {
    if (uri.scheme == 'blogapp' && uri.host == 'login-callback') {
      final code = uri.queryParameters['code'];
      if (code != null) {
        AuthRepository.instance.handleAuthCallback(code);
      }
    }
  });

  runApp(MyApp());
}

final GlobalKey<NavigatorState> mainNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final log = getLogger();
  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    log.d('Debug-Nachricht aus der build-Methode.');
    log.i('Info-Nachricht aus der build-Methode.');
    log.e('Error-Nachricht aus der build-Methode.');
    return MaterialApp.router(
      routerConfig: appRouter,
      title: "Interaction and State",
      debugShowCheckedModeBanner: false,
      theme: _initializeAppTheme(Brightness.light),
      darkTheme: _initializeAppTheme(Brightness.dark),
    );
  }

  ThemeData _initializeAppTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: brightness,
      ),
      textTheme: const TextTheme(titleLarge: TextStyle(fontSize: 20)),
    );
  }
}
