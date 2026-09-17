import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _k = 'sb.themeMode';

  @override
  ThemeMode build() {
    var alive = true;
    ref.onDispose(() => alive = false);
    Future.microtask(() async {
      final raw = (await SharedPreferences.getInstance()).getString(_k);
      final next = switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (alive) state = next;
    });
    return ThemeMode.system;
  }

  Future<void> toggleFromBrightness(Brightness current) {
    return setMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await (await SharedPreferences.getInstance()).setString(_k, value);
  }
}
