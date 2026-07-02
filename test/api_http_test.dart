import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:taiwanbus_flutter/core/api_http.dart';

void main() {
  test('API headers advertise Brotli before gzip', () {
    expect(apiJsonHeaders['Accept-Encoding'], 'br, gzip');
    expect(apiJsonHeaders['Accept'], 'application/json');
  });

  test('apiResponseText decodes Brotli response bodies', () {
    const encoded = <int>[
      139,
      5,
      128,
      104,
      101,
      108,
      108,
      111,
      32,
      98,
      114,
      111,
      116,
      108,
      105,
      3,
    ];
    final response = http.Response.bytes(
      encoded,
      200,
      headers: const {'Content-Encoding': 'br'},
    );

    expect(apiResponseText(response), 'hello brotli');
  });
}
