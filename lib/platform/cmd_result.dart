/// Output of one MEGAcmd command (platform-neutral, unlike `ProcessResult`).
class CmdResult {
  const CmdResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  /// stdout and stderr together — MEGAcmd prints errors on either.
  String get output => '$stdout\n$stderr';
}
