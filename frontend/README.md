# Second Brain — Flutter (Phase 0)

This folder is **source-complete** for S0 (login/register/lockout + router guard + Dio refresh). Platform folders (`android/`, `ios/`, `web/`) are created on your machine:

```bash
cd frontend
flutter create . --project-name second_brain --org app.secondbrain --platforms=android,ios,web
# Keep existing lib/, pubspec.yaml, test/ if asked.
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
```

After `flutter create`, set the Android applicationId / iOS bundle to `app.secondbrain.frontend` if it landed as `app.secondbrain.second_brain`.

Android emulator API host: `http://10.0.2.2:8000/v1`.
