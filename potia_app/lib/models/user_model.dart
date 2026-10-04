class UserModel {
  const UserModel({required this.id, required this.name, required this.email});

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );

  final int id;
  final String name;
  final String email;

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}
