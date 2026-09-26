import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/app_state.dart';
import 'ui/home/home_page.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(ZemoteApp(app: app));
}

class ZemoteApp extends StatelessWidget {
  const ZemoteApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'Zemote',
        debugShowCheckedModeBanner: false,
        theme: buildZTheme(Brightness.light),
        darkTheme: buildZTheme(Brightness.dark),
        themeMode: switch (app.themeMode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        localeResolutionCallback: (locale, supported) =>
            locale?.languageCode == 'zh' ? const Locale('zh') : const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1) * app.textScale),
          ),
          child: child!,
        ),
        home: HomePage(app: app),
      ),
    );
  }
}
