import 'dart:isolate';

Future<R> runHeavy<R>(R Function() computation) => Isolate.run(computation);
