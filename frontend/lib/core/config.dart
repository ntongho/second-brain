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

const kAppVersion = '1.1.1';
