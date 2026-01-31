import 'package:computing_blog/core/compact_printer.dart';
import 'package:logger/logger.dart';

Logger getLogger() {
  return Logger(
    printer: CompactPrinter(),
    level: Level.debug,
  );
}