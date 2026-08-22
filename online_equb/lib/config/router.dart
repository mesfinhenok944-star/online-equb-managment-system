import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/equb/equb_list_screen.dart';
import '../screens/equb/equb_detail_screen.dart';
import '../screens/equb/create_equb_screen.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_users_screen.dart';
import '../screens/admin/admin_payments_screen.dart';
import '../screens/super_admin/super_admin_dashboard_screen.dart';
import '../screens/super_admin/super_admin_admin_form_screen.dart';
import '../screens/super_admin/super_admin_settings_screen.dart';
import '../screens/super_admin/super_admin_create_equb_screen.dart';

GoRouter appRouter(AuthProvider auth) => GoRouter(
      initialLocation: '/home',
      redirect: (context, state) {
        final loggedIn = auth.isLoggedIn;
        final loc = state.matchedLocation;
        final onAuth = loc == '/login' || loc == '/register';
        final isPublic = loc == '/home' ||
            loc == '/equbs' ||
            loc.startsWith('/equbs/') ||
            loc == '/profile' ||
            onAuth;

        // If not logged in and trying to access a protected route, go to login
        if (!loggedIn && !isPublic) return '/login';

        // If logged in and trying to access auth pages (/login or /register), send to appropriate home/dashboard
        if (loggedIn && onAuth) {
          if (auth.isSuperAdmin) return '/super-admin';
          if (auth.isAdmin) return '/admin';
          return '/home';
        }
        return null;
      },
      routes: [
        // ── auth ──────────────────────────────────────────────────────────
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

        // ── regular user ──────────────────────────────────────────────────
        GoRoute(
          path: '/home',
          builder: (_, __) => const HomeScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            if (a.isSuperAdmin) return '/super-admin';
            if (a.isAdmin) return '/admin';
            return null;
          },
        ),
        GoRoute(path: '/equbs', builder: (_, __) => const EqubListScreen()),
        GoRoute(
          path: '/equbs/:id',
          builder: (_, state) =>
              EqubDetailScreen(equbId: state.pathParameters['id']!),
        ),
        GoRoute(
            path: '/equbs/create',
            builder: (_, __) => const CreateEqubScreen()),
        GoRoute(
          path: '/payment/:equbId/:participantId/:amount',
          builder: (_, state) => PaymentScreen(
            equbId: state.pathParameters['equbId']!,
            participantId: state.pathParameters['participantId']!,
            amount: double.tryParse(state.pathParameters['amount'] ?? '0') ?? 0,
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            if (!a.isLoggedIn) return '/login';
            if (a.isSuperAdmin) return '/super-admin';
            if (a.isAdmin) return '/admin';
            return null;
          },
        ),

        // ── admin ─────────────────────────────────────────────────────────
        GoRoute(
          path: '/admin',
          builder: (_, __) => const AdminDashboardScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            if (a.isAdmin && !a.isSuperAdmin) return null;
            if (a.isSuperAdmin) return '/super-admin';
            return '/home';
          },
        ),
        GoRoute(
            path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
        GoRoute(
            path: '/admin/payments',
            builder: (_, __) => const AdminPaymentsScreen()),

        // ── super admin ───────────────────────────────────────────────────
        GoRoute(
          path: '/super-admin',
          builder: (_, __) => const SuperAdminDashboardScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            return a.isSuperAdmin ? null : '/home';
          },
        ),
        GoRoute(
          path: '/super-admin/add-admin',
          builder: (_, __) => const SuperAdminAdminFormScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            return a.isSuperAdmin ? null : '/home';
          },
        ),
        GoRoute(
          path: '/super-admin/edit-admin',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return SuperAdminAdminFormScreen(editData: extra);
          },
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            return a.isSuperAdmin ? null : '/home';
          },
        ),
        GoRoute(
          path: '/super-admin/settings',
          builder: (_, __) => const SuperAdminSettingsScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            return a.isSuperAdmin ? null : '/home';
          },
        ),
        GoRoute(
          path: '/super-admin/add-equb-level',
          builder: (_, __) => const SuperAdminCreateEqubScreen(),
          redirect: (context, state) {
            final a = context.read<AuthProvider>();
            return a.isSuperAdmin ? null : '/home';
          },
        ),
      ],
    );
