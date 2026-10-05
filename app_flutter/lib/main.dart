import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart'; // gerado por: flutterfire configure
import 'screens/dashboard_screen.dart';
import 'screens/lista_screen.dart';
import 'screens/login_screen.dart';
import 'screens/quarentena_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const BancadaApp());
}

class BancadaApp extends StatelessWidget {
  const BancadaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventario Preditivo - URE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FD0),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FD0),
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Decide o que mostrar conforme o estado de autenticacao.
///
/// Este widget existe porque as regras do Firestore (firestore.rules) exigem
/// `request.auth != null`. Sem usuario autenticado, toda leitura do banco
/// retorna erro de permissao. O AuthGate garante que o painel so e montado
/// depois que ha sessao valida.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().mudancasDeEstado,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.hasData ? const HomeShell() : const LoginScreen();
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _auth = AuthService();
  int _aba = 0;
  String _filtroInventario = 'todas';

  static const _titulos = ['Painel', 'Inventario', 'Quarentena'];
  
  List<Widget> get _telas => [
        DashboardScreen(
          onNavegar: (aba, {filtro}) {
            setState(() {
              _aba = aba;
              if (filtro != null) {
                _filtroInventario = filtro;
              }
            });
          },
        ),
        ListaScreen(filtroInicial: _filtroInventario),
        const QuarentenaScreen(),
      ];

  Future<void> _confirmarSaida() async {
    final sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da conta'),
        content: Text('Encerrar a sessao de ${_auth.emailAtual}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (sair == true) await _auth.sair();
  }

  @override
  Widget build(BuildContext context) {
    final largo = MediaQuery.of(context).size.width > 800;
    if (_aba >= _telas.length) _aba = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_aba]),
        centerTitle: false,
        actions: [
          if (largo)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(_auth.emailAtual,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.outline)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _confirmarSaida,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: largo
          ? Row(children: [
              NavigationRail(
                selectedIndex: _aba,
                onDestinationSelected: (i) => setState(() => _aba = i),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Painel')),
                  NavigationRailDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: Text('Inventario')),
                  NavigationRailDestination(
                      icon: Icon(Icons.help_outline),
                      selectedIcon: Icon(Icons.help),
                      label: Text('Quarentena')),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _telas[_aba]),
            ])
          : _telas[_aba],
      bottomNavigationBar: largo
          ? null
          : NavigationBar(
              selectedIndex: _aba,
              onDestinationSelected: (i) => setState(() => _aba = i),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined), label: 'Painel'),
                NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined), label: 'Inventario'),
                NavigationDestination(
                    icon: Icon(Icons.help_outline), label: 'Quarentena'),
              ],
            ),
    );
  }
}
