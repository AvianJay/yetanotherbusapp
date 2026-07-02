import 'dart:convert';

import 'package:brotli/brotli.dart' as brotli;
import 'package:http/http.dart' as http;

const apiAcceptedEncodings = 'br, gzip';
const apiCompressionHeaders = <String, String>{
  'Accept-Encoding': apiAcceptedEncodings,
};
const apiJsonHeaders = <String, String>{
  'Accept': 'application/json',
  ...apiCompressionHeaders,
};
const apiJsonContentHeaders = <String, String>{
  ...apiJsonHeaders,
  'Content-Type': 'application/json',
};

List<int> apiResponseBodyBytes(http.Response response) {
  List<int> bytes = response.bodyBytes;
  final encodings = _contentEncodings(response);
  for (final encoding in encodings.reversed) {
    switch (encoding) {
      case 'br':
        bytes = _tryDecode(() => brotli.brotli.decode(bytes), bytes);
        break;
      case 'gzip':
      case 'x-gzip':
      case 'identity':
        break;
    }
  }
  return bytes;
}

String apiResponseText(http.Response response) {
  return utf8.decode(apiResponseBodyBytes(response));
}

Object? apiDecodeJsonResponse(http.Response response) {
  return jsonDecode(apiResponseText(response));
}

List<String> _contentEncodings(http.Response response) {
  final header = response.headers.entries
      .where((entry) => entry.key.toLowerCase() == 'content-encoding')
      .map((entry) => entry.value)
      .firstOrNull;
  if (header == null || header.trim().isEmpty) {
    return const [];
  }
  return header
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

List<int> _tryDecode(List<int> Function() decode, List<int> fallback) {
  try {
    return decode();
  } catch (_) {
    return fallback;
  }
}
