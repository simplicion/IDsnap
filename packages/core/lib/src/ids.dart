import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generates a random, collision-resistant identifier (UUID v4).
String newId() => _uuid.v4();
