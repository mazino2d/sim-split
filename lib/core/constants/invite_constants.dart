import 'package:simsplit/core/constants/app_env.dart';

/// Invite links open `<web app>/join/<token>` (`https://simsplit.web.app` in
/// prd, `https://simsplit-dev.web.app` in dev): the web app on Firebase
/// Hosting, and the Android app through App Links (R-3 P6).
final inviteLinkBase = inviteLinkBaseFor(appEnv);

Uri inviteLinkBaseFor(AppEnv env) => env.webOrigin.resolve('/join');
