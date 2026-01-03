class AppException implements Exception {
  final String message;
  AppException(this.message);
}

class NetworkException extends AppException {
  NetworkException() : super('Keine Internetverbindung');
}

class ServerException extends AppException {
  ServerException(String? details) : super('Serverfehler: $details');
}