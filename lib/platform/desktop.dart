/// Desktop-only services: single-instance coordination for scheduled checks,
/// installing the schedule with the operating system, and remembering the
/// vault key in the system keychain.
///
/// Desktop builds (macOS, Windows) get the `dart:io` implementation; the web
/// build gets a stub where everything reports "not supported".
library;

export 'desktop_stub.dart' if (dart.library.io) 'desktop_io.dart';
