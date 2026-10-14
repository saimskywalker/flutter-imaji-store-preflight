import 'dart:io';

import 'package:imaji_store_preflight/imaji_store_preflight.dart';

Future<void> main(List<String> arguments) async {
  exitCode = runCli(arguments);
  await stdout.flush();
}
