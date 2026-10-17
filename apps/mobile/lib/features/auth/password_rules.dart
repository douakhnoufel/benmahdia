/// What a patient's password must contain (PRD 4.1). The server checks the
/// same rules; this list only drives the live checklist.
enum PasswordRule {
  length,
  letter,
  digit;

  static const minLength = 8;

  bool isMetBy(String password) => switch (this) {
    PasswordRule.length => password.length >= minLength,
    PasswordRule.letter => RegExp(r'\p{L}', unicode: true).hasMatch(password),
    PasswordRule.digit => RegExp(r'[0-9٠-٩]').hasMatch(password),
  };

  static bool allMetBy(String password) =>
      values.every((rule) => rule.isMetBy(password));
}
