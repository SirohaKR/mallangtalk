import 'dart:collection';
import 'dart:convert';
import 'package:flutter/painting.dart';

/// Reuse the byte buffer: MemoryImage equality uses the bytes' identity.
/// Bounded so inline photos do not grow a second unbounded application cache.
class InlineImageCache {
  InlineImageCache(
      {this.maxEntries = 24, this.maxSourceCharacters = 8 * 1024 * 1024});
  final int maxEntries;
  final int maxSourceCharacters;
  final _images = LinkedHashMap<String, MemoryImage>();
  int _characters = 0;

  MemoryImage? providerFor(String source) {
    final existing = _images.remove(source);
    if (existing != null) {
      _images[source] = existing;
      return existing;
    }
    final comma = source.indexOf(',');
    if (comma < 0 || !source.startsWith('data:')) return null;
    final MemoryImage provider;
    try {
      provider = MemoryImage(base64Decode(source.substring(comma + 1)));
    } on FormatException {
      return null;
    }
    if (source.length > maxSourceCharacters || maxEntries < 1) return provider;
    while (_images.isNotEmpty &&
        (_images.length >= maxEntries ||
            _characters + source.length > maxSourceCharacters)) {
      final oldest = _images.keys.first;
      _images.remove(oldest);
      _characters -= oldest.length;
    }
    _images[source] = provider;
    _characters += source.length;
    return provider;
  }
}
