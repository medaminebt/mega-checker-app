/// Things only a desktop app can do: run the MEGAcmd command-line tools and
/// show a file in Finder / Explorer.
///
/// Desktop builds (macOS, Windows) get the `dart:io` implementation; the web
/// build gets a stub that reports both as unavailable, so the same UI code
/// compiles everywhere.
library;

export 'native_stub.dart' if (dart.library.io) 'native_io.dart';
