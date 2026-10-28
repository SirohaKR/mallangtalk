import 'package:flutter_test/flutter_test.dart';
import 'package:mallangtalk/core/network/api_endpoint.dart';

void main() {
  test('same-origin API and separately hosted API resolve independently', () {
    final page = Uri.parse('https://talk.example.com/chat/one');
    expect(apiOrigin(page, configured: '')?.origin, 'https://talk.example.com');
    final origin = apiOrigin(page, configured: 'https://api.example.com/');
    expect(origin?.resolve('/api/images/one').toString(),
        'https://api.example.com/api/images/one');
    expect(
        apiOrigin(Uri.parse('file:///app'),
                configured: 'https://api.example.com')
            ?.origin,
        'https://api.example.com');
    expect(() => apiOrigin(page, configured: 'https://api.example.com/api'),
        throwsFormatException);
  });
}
