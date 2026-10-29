class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.token,
  });
  final String id, email, firstName, lastName, role, token;
  String get fullName => '$firstName $lastName';
  bool get isCitizen => role == 'CITIZEN';

  AuthenticatedUser withName(String firstName, String lastName) =>
      AuthenticatedUser(
        id: id,
        email: email,
        firstName: firstName,
        lastName: lastName,
        role: role,
        token: token,
      );

  factory AuthenticatedUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthenticatedUser(
      id: user['id'] as String,
      email: user['email'] as String,
      firstName: user['firstName'] as String,
      lastName: user['lastName'] as String,
      role: user['role'] as String,
      token: json['token'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'user': {
      'id': id,
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'role': role,
    },
    'token': token,
  };
}
