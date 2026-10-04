import 'user_model.dart';

class AuthSession {
  const AuthSession({required this.accessToken, required this.expiresIn, required this.user});

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 0,
        user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String accessToken;
  final int expiresIn;
  final UserModel user;
}
