import 'dart:io';

import 'package:budgetwise_server/budgetwise_server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final Env env;
  try {
    env = Env.fromPlatform();
  } on ConfigException catch (error) {
    // Fail at startup, loudly. A server that boots without a signing secret and
    // only fails when someone tries to sign in looks healthy while being
    // useless.
    stderr.writeln('Configuration error:\n${error.message}');
    exit(78); // EX_CONFIG
  }

  final mongo = await Mongo.connect(
    env.mongoUri,
    databaseName: env.databaseName,
  );
  await mongo.ensureIndexes();
  stdout.writeln('Connected to MongoDB (${env.databaseName})');

  final api = BudgetWiseApi(env: env, mongo: mongo);
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, env.port);
  stdout.writeln('BudgetWise API listening on :${server.port}');

  // Close the database before the process goes away, so in-flight writes are
  // not cut mid-statement by the container runtime.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      stdout.writeln('Shutting down…');
      await server.close();
      await mongo.close();
      exit(0);
    });
  }
}
