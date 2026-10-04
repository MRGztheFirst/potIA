class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}
