/// One row of the accounts database (the CSV). `notes` is mutable because the
/// app appends timestamped login results to it and writes it back to the CSV.
class Account {
  String email;
  String password;
  String notes;

  /// Transient UI state for the current run — NOT written to the CSV.
  /// One of: '—', 'running', 'ok', or a short failure label.
  String lastResult;

  Account({
    required this.email,
    required this.password,
    this.notes = '',
    this.lastResult = '—',
  });
}

/// Outcome of a single login attempt.
enum LoginOutcome {
  success,
  wrongCredentials, // MEGA: "invalid email or password"
  invalidEmail, // malformed address, rejected before contacting MEGA
  needs2fa, // account has 2FA (this app doesn't handle codes)
  megacmdMissing, // MEGAcmd not installed / not found
  error, // anything else (timeout, network, unexpected output)
}

class LoginResult {
  final LoginOutcome outcome;
  final String message; // human-readable detail

  LoginResult(this.outcome, this.message);

  bool get ok => outcome == LoginOutcome.success;

  /// Short phrase appended to the account's notes after the timestamp.
  String get noteText {
    switch (outcome) {
      case LoginOutcome.success:
        return 'login OK';
      case LoginOutcome.wrongCredentials:
        return 'login FAILED: wrong email or password';
      case LoginOutcome.invalidEmail:
        return 'login FAILED: invalid email address';
      case LoginOutcome.needs2fa:
        return 'login FAILED: account needs 2FA';
      case LoginOutcome.megacmdMissing:
        return 'login FAILED: MEGAcmd not installed';
      case LoginOutcome.error:
        return 'login FAILED: $message';
    }
  }

  /// Short label for the result chip in the table.
  String get chipLabel {
    switch (outcome) {
      case LoginOutcome.success:
        return 'ok';
      case LoginOutcome.wrongCredentials:
        return 'wrong email/password';
      case LoginOutcome.invalidEmail:
        return 'invalid email';
      case LoginOutcome.needs2fa:
        return '2FA needed';
      case LoginOutcome.megacmdMissing:
        return 'MEGAcmd missing';
      case LoginOutcome.error:
        return 'error';
    }
  }
}
