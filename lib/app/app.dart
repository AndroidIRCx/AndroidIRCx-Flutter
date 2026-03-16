import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:flutter/material.dart';

class AndroidIrcxApp extends StatelessWidget {
  const AndroidIrcxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AndroidIRCx Flutter',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const BootstrapScreen(),
    );
  }
}
