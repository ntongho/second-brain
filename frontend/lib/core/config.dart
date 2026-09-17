/// Compile-time API root (OpenAPI servers url, including `/v1`).
///
/// ```
/// flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
/// flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
/// ```
const kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000/v1',
);

/// Phone/emulator cannot reach the PC via localhost. Set API_BASE_URL to the
/// machine LAN IP (device) or 10.0.2.2 (Android emulator).
bool get kApiIsLoopback {
  final host = Uri.tryParse(kApiBaseUrl)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

const kAppVersion = '1.1.1';

/// Google Cloud **Web** OAuth client ID (used as serverClientId). Empty = hide/disable Google button.
/// ```
/// flutter run ... --dart-define=GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
/// ```
const kGoogleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
