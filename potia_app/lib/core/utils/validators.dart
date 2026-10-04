class Validators {
  Validators._();

  static final RegExp _emailRegex = RegExp(r'^[\w.+\-]+@([\w\-]+\.)+[A-Za-z]{2,}$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-zÀ-ÿ]');
  static final RegExp _hasDigit = RegExp(r'\d');

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe seu nome';
    if (text.length < 2) return 'Nome muito curto';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe seu e-mail';
    if (!_emailRegex.hasMatch(text)) return 'E-mail inválido';
    return null;
  }

  static String? newPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Crie uma senha';
    if (text.length < 8) return 'A senha deve ter pelo menos 8 caracteres';
    if (!_hasLetter.hasMatch(text)) return 'Inclua pelo menos uma letra';
    if (!_hasDigit.hasMatch(text)) return 'Inclua pelo menos um número';
    return null;
  }

  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Informe sua senha' : null;

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return 'Confirme sua senha';
      if (value != original()) return 'As senhas não coincidem';
      return null;
    };
  }
}
