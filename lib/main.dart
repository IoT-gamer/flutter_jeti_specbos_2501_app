import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'dashboard_screen.dart';
import 'jeti_cubit.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => JetiCubit(),
      child: MaterialApp(
        title: 'Jeti Specbos 2501 App',
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.tealAccent,
            surface: Color(0xFF16181D),
          ),
        ),
        home: const DashboardScreen(),
      ),
    );
  }
}
