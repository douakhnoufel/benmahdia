import 'package:flutter/material.dart';

import '../auth/auth_flow.dart';
import '../profile/profile_flow.dart';
import 'welcome_screen.dart';

/// Builds the signed-out entry screen. Call [onOpenHome] after authentication
/// (and, for sign-up, after the profile declaration flow).
Widget welcomeEntry(
  BuildContext context, {
  Key? key,
  required VoidCallback onOpenHome,
}) => WelcomeScreen(
  key: key,
  onCreateAccount: () => openSignUp(
    context,
    onSignedIn: (_) => openProfile(context, afterFinish: onOpenHome),
  ),
  onLogin: () => openLogin(context, onSignedIn: (_) => onOpenHome()),
);
