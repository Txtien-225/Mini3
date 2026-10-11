# Mini Project 3 — OCR Expense Tracker

## Run

Install Flutter 3.x and Dart 3, then from this folder run:

```bash
flutter create .
flutter pub get
flutter run -d chrome
```

For Android/iOS, open an emulator or connect a device and run `flutter run`. On Android/iOS, the camera path uses Google ML Kit Text Recognition on-device. On Web, camera selection falls back to the receipt-text field because the ML Kit Flutter plugin is native-only.

## Included

- Responsive Flutter Material 3 dashboard, scanner/review form, and history screen.
- Receipt parser for VND formats such as `150,000 VND`, `150.000 đ`, dates, and merchant names.
- Native OCR adapter with a Web-safe fallback.
- Category donut visualization drawn using `CustomPainter`.
- Persistent cross-platform local transaction storage using `shared_preferences` (easy to swap for SQLite/Isar if your rubric requires that exact engine).
