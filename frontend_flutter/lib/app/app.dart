import 'package:flutter/material.dart';
import 'router.dart';

class DPPAApp extends StatelessWidget {
  const DPPAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Digital Privacy Protection App',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8)),
      ),
    );
  }
}
