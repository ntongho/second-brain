import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// GIS button (id token). Do not use plugin [GoogleSignIn.signIn] on web.
Widget buildGoogleSignInButton() {
  return gsi.renderButton();
}
