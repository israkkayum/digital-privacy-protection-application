import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/utils/session_guard.dart';
import 'shell_scaffold.dart';
import 'router_refresh.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';

import '../features/enrollment/presentation/enrollment_intro_screen.dart';
import '../features/enrollment/presentation/enrollment_camera_screen.dart';
import '../features/enrollment/presentation/enrollment_processing_screen.dart';
import '../features/enrollment/presentation/enrollment_success_screen.dart';

import '../features/home/presentation/home_screen.dart';

import '../features/verify/presentation/verify_link_screen.dart';
import '../features/verify/presentation/scan_processing_screen.dart';
import '../features/verify/presentation/verify_result_screen.dart';
import '../features/verify/presentation/live_verify_camera_screen.dart';
import '../features/verify/presentation/live_verify_processing_screen.dart';
import '../features/verify/presentation/live_verify_result_screen.dart';

import '../features/reports/presentation/reports_screen.dart';
import '../features/reports/presentation/report_details_screen.dart';
import '../features/reports/presentation/report_create_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),

  redirect: (context, state) async {
    final loc = state.uri.toString();

    final user = FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;
    final verified = user?.emailVerified ?? false;
    final enrolled = await SessionGuard.isEnrolled();

    // ---- route groups ----
    final isLogin = loc.startsWith('/login');
    final isRegister = loc.startsWith('/register');
    final isForgot = loc.startsWith('/forgot-password');
    final isVerifyEmail = loc.startsWith('/verify-email');

    final isAuthRoute = isLogin || isRegister || isForgot || isVerifyEmail;

    final isEnrollRoute = loc.startsWith('/enroll');

    // 1) Not logged in -> only allow auth routes
    if (!loggedIn) {
      return isAuthRoute ? null : '/login';
    }

    // 2) Logged in but NOT verified -> force verify-email
    if (!verified) {
      return isVerifyEmail ? null : '/verify-email';
    }

    // 3) Verified but NOT enrolled -> force enrollment (block everything else)
    if (!enrolled) {
      return isEnrollRoute ? null : '/enroll';
    }

    // 4) Enrolled -> block auth + enrollment pages
    if (enrolled && (isAuthRoute || isEnrollRoute)) {
      return '/home';
    }

    return null;
  },

  routes: [
    // ---------------- AUTH (no shell) ----------------
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(
      path: '/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (_, __) => const VerifyEmailScreen(),
    ),

    // ---------------- ENROLLMENT (no shell) ----------------
    GoRoute(path: '/enroll', builder: (_, __) => const EnrollmentIntroScreen()),
    GoRoute(
      path: '/enroll/camera',
      builder: (_, __) => const EnrollmentCameraScreen(),
    ),
    GoRoute(
      path: '/enroll/processing',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final paths = (extra?['paths'] as List?)?.cast<String>() ?? <String>[];
        return EnrollmentProcessingScreen(posePaths: paths);
      },
    ),
    GoRoute(
      path: '/enroll/success',
      builder: (_, __) => const EnrollmentSuccessScreen(),
    ),

    // ---------------- MAIN APP (ShellRoute) ----------------
    ShellRoute(
      pageBuilder: (context, state, child) =>
          NoTransitionPage(child: ShellScaffold(child: child)),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),

        GoRoute(
          path: '/verify',
          builder: (_, __) => const VerifyLinkScreen(),
          routes: [
            GoRoute(
              path: 'processing',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return ScanProcessingScreen(
                  link: extra['link'] as String?,
                  uploadPath: extra['uploadPath'] as String?,
                  sourceType: extra['sourceType'] as String? ?? 'link',
                  sourceLabel: extra['sourceLabel'] as String?,
                );
              },
            ),
            GoRoute(
              path: 'result',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return VerifyResultScreen(
                  link: extra['link'] as String?,
                  sourceType: extra['sourceType'] as String? ?? 'link',
                  sourceLabel: extra['sourceLabel'] as String?,
                  matchFound: extra['matchFound'] as bool? ?? false,
                  confidence: (extra['confidence'] as num?)?.toDouble() ?? 0.0,
                  threshold: (extra['threshold'] as num?)?.toDouble() ?? 0.72,
                  thresholdMode: extra['thresholdMode'] as String? ?? 'global',
                  consentExists: extra['consentExists'] as bool? ?? false,
                  reason: extra['reason'] as String?,
                  scanId: extra['scanId'] as String?,
                );
              },
            ),
            GoRoute(
              path: 'live',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return LiveVerifyCameraScreen(
                  nextRoute: extra['next'] as String?,
                  nextExtra: extra['nextExtra'],
                );
              },
              routes: [
                GoRoute(
                  path: 'processing',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>? ?? {};
                    final paths = (extra['paths'] as List? ?? const [])
                        .cast<String>();
                    return LiveVerifyProcessingScreen(
                      posePaths: paths,
                      blinkOk: extra['blinkOk'] as bool? ?? true,
                      nextRoute: extra['next'] as String?,
                      nextExtra: extra['nextExtra'],
                    );
                  },
                ),
                GoRoute(
                  path: 'result',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>? ?? {};
                    return LiveVerifyResultScreen(
                      isMatch: extra['isMatch'] as bool? ?? false,
                      score: extra['score'] as double? ?? 0.0,
                      threshold: extra['threshold'] as double? ?? 0.0,
                      reason: extra['reason'] as String?,
                      lockoutUntilMs: extra['lockoutUntilMs'] as int?,
                      nextRoute: extra['next'] as String?,
                      nextExtra: extra['nextExtra'],
                    );
                  },
                ),
              ],
            ),
          ],
        ),

        GoRoute(
          path: '/reports',
          builder: (_, __) => const ReportsScreen(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return ReportCreateScreen(
                  initialPlatform: extra['platform'] as String?,
                  initialUrl: extra['url'] as String?,
                  initialScanId: extra['scanId'] as String?,
                  initialScore: (extra['score'] as num?)?.toDouble(),
                  initialThreshold: (extra['threshold'] as num?)?.toDouble(),
                  initialReason: extra['reason'] as String?,
                  autoSend: extra['autoSend'] as bool? ?? false,
                );
              },
            ),
            GoRoute(
              path: 'details',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return ReportDetailsScreen(reportId: extra['id'] as String?);
              },
            ),
          ],
        ),

        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    ),
  ],
);
