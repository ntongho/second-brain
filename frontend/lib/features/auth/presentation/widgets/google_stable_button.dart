import 'package:flutter/material.dart';
import 'package:second_brain/features/auth/presentation/widgets/google_button.dart';

/// GIS [renderButton] must be created once. Rebuilding it each keystroke
/// re-inits Google ("Getting ready") and the button shakes.
class StableGoogleButton extends StatefulWidget {
  const StableGoogleButton({super.key});

  @override
  State<StableGoogleButton> createState() => _StableGoogleButtonState();
}

class _StableGoogleButtonState extends State<StableGoogleButton> {
  Widget? _button;

  @override
  void initState() {
    super.initState();
    _button = buildGoogleSignInButton();
  }

  @override
  Widget build(BuildContext context) => _button ?? const SizedBox.shrink();
}
