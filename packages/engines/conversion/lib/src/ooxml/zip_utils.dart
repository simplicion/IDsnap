import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:xml/xml.dart';

/// Opens an OOXML (ZIP) container. Throws [AppFailure] with
/// `passwordProtected` for encrypted packages and `corruptFile` otherwise.
Archive openPackage(Uint8List bytes) {
  // Password-protected Office files are OLE compound documents, not ZIPs.
  if (bytes.length >= 8 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0) {
    throw const AppFailure(FailureCode.passwordProtected);
  }
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw const AppFailure(FailureCode.corruptFile);
  }
  // General purpose flag bit 0 marks an encrypted entry.
  if (bytes.length > 7 && (bytes[6] & 0x01) == 0x01) {
    throw const AppFailure(FailureCode.passwordProtected);
  }
  try {
    return ZipDecoder().decodeBytes(bytes);
  } on Object catch (e, st) {
    throw AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st);
  }
}

/// Reads and parses an XML part, or returns null when missing.
XmlDocument? readXmlPart(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  final bytes = file.readBytes();
  if (bytes == null) return null;
  try {
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  } on XmlException catch (e, st) {
    throw AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st);
  }
}

XmlDocument requireXmlPart(Archive archive, String name) =>
    readXmlPart(archive, name) ??
    (throw const AppFailure(FailureCode.corruptFile));

/// Local (namespace-free) name of an element.
String localName(XmlElement e) => e.name.local;

/// Attribute by local name regardless of prefix.
String? attr(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// The relationship id (`r:id`) of an element — distinct from a plain `id`
/// attribute that elements like `p:sldId` also carry.
String? relationshipId(XmlElement e) {
  for (final a in e.attributes) {
    if (a.name.local == 'id' && a.name.prefix != null) return a.value;
  }
  return null;
}

/// Descendant elements with [local] name, in document order.
Iterable<XmlElement> descendantsNamed(XmlNode node, String local) => node
    .descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

/// Resolves relationship ids to targets from a `.rels` part.
Map<String, String> readRelationships(Archive archive, String relsPath) {
  final doc = readXmlPart(archive, relsPath);
  if (doc == null) return const {};
  return {
    for (final r in descendantsNamed(doc, 'Relationship'))
      if (attr(r, 'Id') != null && attr(r, 'Target') != null)
        attr(r, 'Id')!: attr(r, 'Target')!,
  };
}

/// Joins a relationship target relative to the folder of [basePart].
String resolveTarget(String basePart, String target) {
  if (target.startsWith('/')) return target.substring(1);
  final parts = basePart.split('/')..removeLast();
  for (final seg in target.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Escapes text for XML content/attributes and drops characters that XML 1.0
/// forbids (most C0 controls), which OCR output occasionally contains.
String xmlEscape(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x9 ||
        r == 0xA ||
        r == 0xD ||
        (r >= 0x20 && r <= 0xD7FF) ||
        (r >= 0xE000 && r <= 0xFFFD) ||
        r >= 0x10000) {
      switch (r) {
        case 0x26:
          b.write('&amp;');
        case 0x3C:
          b.write('&lt;');
        case 0x3E:
          b.write('&gt;');
        case 0x22:
          b.write('&quot;');
        case 0x27:
          b.write('&apos;');
        default:
          b.writeCharCode(r);
      }
    }
  }
  return b.toString();
}

/// Builds a ZIP from part name → content (String or bytes).
Uint8List buildPackage(Map<String, Object> parts) {
  final archive = Archive();
  for (final e in parts.entries) {
    final v = e.value;
    archive.addFile(
      v is String
          ? ArchiveFile.bytes(e.key, utf8.encode(v))
          : ArchiveFile.bytes(e.key, v as List<int>),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}
