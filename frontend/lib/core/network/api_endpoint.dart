/// Set --dart-define=API_BASE_URL=https://api.example.com for a separate API.
/// Empty means the browser's origin, with /api proxied by the frontend server.
const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

Uri? apiOrigin(Uri page, {String configured = configuredApiBaseUrl}) {
  final uri =
      configured.trim().isEmpty ? page : Uri.tryParse(configured.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) return null;
  if (configured.trim().isNotEmpty &&
      (uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/'))) {
    throw const FormatException(
        'API_BASE_URL must be an HTTP(S) origin without a path.');
  }
  return Uri.parse(uri.origin);
}

String resolveApiAsset(String path) =>
    (apiOrigin(Uri.base) ?? Uri.base).resolve(path).toString();
