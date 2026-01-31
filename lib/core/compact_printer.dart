import 'package:logger/logger.dart';

class CompactPrinter extends LogPrinter {
  final PrettyPrinter _pretty = PrettyPrinter(
    colors: false,
    lineLength: 90,
    noBoxingByDefault: true,
    printEmojis: true,
    printTime: false,
    methodCount: 0,        // default: kein Stack
    errorMethodCount: 5,   // nur für Errors relevant
  );

  @override
  List<String> log(LogEvent event) {
    // Für warn & error: Stacktrace aktivieren
    if (event.level == Level.warning || event.level == Level.error) {
      final withStack = PrettyPrinter(
        colors: false,
        lineLength: 90,
        noBoxingByDefault: true,
        printEmojis: true,
        printTime: false,
        methodCount: 1,        // 👈 obere Zeile AN
        errorMethodCount: 5,
      );
      return withStack.log(event);
    }

    // Für info / debug / trace: ohne obere Zeile
    return _pretty.log(event);
  }
}
