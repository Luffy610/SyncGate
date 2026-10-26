import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncgate/src/app/admin_shell.dart';
import 'package:syncgate/src/app/app_mode.dart';
import 'package:syncgate/src/app/routes.dart';
import 'package:syncgate/src/features/enrolment/details_screen.dart';
import 'package:syncgate/src/features/enrolment/face_capture_screen.dart';
import 'package:syncgate/src/features/enrolment/notice_screen.dart';
import 'package:syncgate/src/features/exceptions/exceptions_screen.dart';
import 'package:syncgate/src/features/gate/gate_screen.dart';
import 'package:syncgate/src/features/gate/manual_entry_screen.dart';
import 'package:syncgate/src/features/reports/muster_grid_screen.dart';
import 'package:syncgate/src/features/reports/reports_screen.dart';
import 'package:syncgate/src/features/settings/backup_screen.dart';
import 'package:syncgate/src/features/settings/settings_hub_screen.dart';
import 'package:syncgate/src/features/settings/settings_pages.dart';
import 'package:syncgate/src/features/setup/camera_step.dart';
import 'package:syncgate/src/features/setup/first_worker_step.dart';
import 'package:syncgate/src/features/setup/kiosk_step.dart';
import 'package:syncgate/src/features/setup/language_step.dart';
import 'package:syncgate/src/features/setup/licence_step.dart';
import 'package:syncgate/src/features/setup/owner_step.dart';
import 'package:syncgate/src/features/setup/shift_step.dart';
import 'package:syncgate/src/features/today/today_screen.dart';
import 'package:syncgate/src/features/unlock/unlock_screen.dart';
import 'package:syncgate/src/features/workers/worker_profile_screen.dart';
import 'package:syncgate/src/features/workers/workers_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds the router. Redirects follow the app mode (frontend plan §3.1).
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(appModeProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.root,
    refreshListenable: refresh,
    redirect: (context, state) {
      final mode = ref.read(appModeProvider);
      final path = state.uri.path;
      if (path == Routes.root) return Routes.homeFor(mode);
      return redirectFor(mode, path);
    },
    routes: [
      GoRoute(
        path: Routes.setupLanguage,
        builder: (c, s) => const LanguageStep(),
      ),
      GoRoute(
        path: Routes.setupLicence,
        builder: (c, s) => const LicenceStep(),
      ),
      GoRoute(path: Routes.setupShift, builder: (c, s) => const ShiftStep()),
      GoRoute(path: Routes.setupCamera, builder: (c, s) => const CameraStep()),
      GoRoute(path: Routes.setupKiosk, builder: (c, s) => const KioskStep()),
      GoRoute(path: Routes.setupOwner, builder: (c, s) => const OwnerStep()),
      GoRoute(
        path: Routes.setupFirstWorker,
        builder: (c, s) => const FirstWorkerStep(),
      ),
      GoRoute(path: Routes.gate, builder: (c, s) => const GateScreen()),
      GoRoute(
        path: Routes.manual,
        builder: (c, s) => const ManualEntryScreen(),
      ),
      GoRoute(path: Routes.unlock, builder: (c, s) => const UnlockScreen()),
      GoRoute(
        path: Routes.exceptions,
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const ExceptionsScreen(),
      ),
      GoRoute(
        path: Routes.enrolDetails,
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const EnrolDetailsScreen(),
      ),
      GoRoute(
        path: Routes.enrolNotice,
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const EnrolNoticeScreen(),
      ),
      GoRoute(
        path: Routes.enrolFace,
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const EnrolFaceScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdminShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.today,
                builder: (c, s) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.workers,
                builder: (c, s) => const WorkersScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (c, s) => WorkerProfileScreen(
                      workerId: s.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                builder: (c, s) => const ReportsScreen(),
                routes: [
                  GoRoute(
                    path: 'muster',
                    builder: (c, s) => const MusterGridScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (c, s) => const SettingsHubScreen(),
                routes: [
                  GoRoute(
                    path: 'backup',
                    builder: (c, s) => const BackupScreen(),
                    routes: [
                      GoRoute(
                        path: 'passphrase',
                        builder: (c, s) => const PassphraseScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'shifts',
                    builder: (c, s) => const ShiftsScreen(),
                  ),
                  GoRoute(
                    path: 'users',
                    builder: (c, s) => const UsersScreen(),
                  ),
                  GoRoute(
                    path: 'tally',
                    builder: (c, s) => const TallyScreen(),
                  ),
                  GoRoute(
                    path: 'language',
                    builder: (c, s) => const LanguageSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'gate',
                    builder: (c, s) => const GateSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'privacy',
                    builder: (c, s) => const PrivacyScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (c, s) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
