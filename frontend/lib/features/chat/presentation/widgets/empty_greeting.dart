import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeen = 'sb.welcomed.v1';

const kReturningGreetings = [
  'Ready when you are',
  'What’s on your mind?',
  'Your library is waiting',
  'Welcome back',
];

class EmptyGreeting extends StatefulWidget {
  const EmptyGreeting({super.key});

  @override
  State<EmptyGreeting> createState() => _EmptyGreetingState();
}

class _EmptyGreetingState extends State<EmptyGreeting> {
  var _title = 'Welcome';

  @override
  void initState() {
    super.initState();
    _pick();
  }

  Future<void> _pick() async {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getBool(_kSeen) != true;
    if (first) {
      await prefs.setBool(_kSeen, true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _title = kReturningGreetings[Random().nextInt(kReturningGreetings.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _title,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.center,
    );
  }
}
