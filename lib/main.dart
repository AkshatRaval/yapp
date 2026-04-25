import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_auth_notifier.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

// Global provider for authNotifier so screens can access it
final authNotifierProvider = Provider<AppAuthNotifier>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    anonKey: AppConstants.supabaseAnonKey,
  );

  // Create once — never recreated
  final authNotifier = AppAuthNotifier(Supabase.instance.client);
  final router = buildRouter(authNotifier);

  runApp(
    ProviderScope(
      overrides: [
        // Inject authNotifier into Riverpod so any screen can access it
        authNotifierProvider.overrideWithValue(authNotifier),
      ],
      child: YappApp(router: router),
    ),
  );
}

class YappApp extends StatelessWidget {
  final GoRouter router;
  const YappApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Yapp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: router,
    );
  }
}
