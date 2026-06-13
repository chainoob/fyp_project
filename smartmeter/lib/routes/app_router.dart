import 'package:go_router/go_router.dart';
import 'package:smartmeter/controllers/provider.dart';
import 'package:smartmeter/screens/register_screen.dart';
import 'package:smartmeter/screens/students/student_shell.dart';
import 'package:smartmeter/screens/staffs/staff_shell.dart';
import 'package:smartmeter/screens/students/analytics_screen.dart';
import 'package:smartmeter/utils/auth_wrapper.dart';

class AppRoutes {
  static const register = '/register';
  static const studentHome = '/student';
  static const staffHome = '/staff';
  static const analytics = '/analytics';
  static const root = '/'; 
}

class AppRouter {
  static GoRouter create(AppAuthProvider auth) {
    return GoRouter(
      initialLocation: AppRoutes.root,
      refreshListenable: auth,
      redirect: (context, state) {
        final loggedIn = auth.loggedIn;
        final isGoingToRoot = state.matchedLocation == AppRoutes.root;
        final isGoingToRegister = state.matchedLocation == AppRoutes.register;

        if (!loggedIn) {
          if (!isGoingToRoot && !isGoingToRegister) {
            return AppRoutes.root;
          }
          return null;
        }

        // User is logged in
        final isStaff = auth.isStaff;
        if (isGoingToRoot) {
          return isStaff ? AppRoutes.staffHome : AppRoutes.studentHome;
        }

        if (isStaff && state.matchedLocation == AppRoutes.studentHome) {
          return AppRoutes.staffHome;
        }

        if (!isStaff && state.matchedLocation == AppRoutes.staffHome) {
          return AppRoutes.studentHome;
        }

        return null;
      },

      routes: [
        GoRoute(
          path: AppRoutes.root,
          builder: (context, state) => const AuthWrapper(),
        ),

        GoRoute(
            path: AppRoutes.register,
            builder: (context, state) {
              final data = state.extra as Map<String, String?>?;
              return RegisterScreen(
                initialMatric: data?['matric'],
                initialEmail: data?['email'],
              );
            }
        ),

        // DASHBOARDS: Accessible via wrapper or direct link
        GoRoute(
            path: AppRoutes.studentHome,
            builder: (context, state) => const StudentShell()
        ),
        GoRoute(
            path: AppRoutes.staffHome,
            builder: (context, state) => const StaffShell()
        ),

        GoRoute(
            path: AppRoutes.analytics, 
            builder: (context, state) => const AnalyticsScreen(),
        ),
      ],
    );
  }
}