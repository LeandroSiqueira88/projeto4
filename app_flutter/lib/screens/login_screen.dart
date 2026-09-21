import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Tela de entrada.
///
/// NAO HA AUTOCADASTRO. As contas sao criadas pelo administrador no console
/// do Firebase (Authentication > Usuarios > Adicionar usuario), e a opcao
/// "Ativar criacao (inscricao)" fica desligada nas configuracoes.
///
/// A razao e institucional: este e um painel de patrimonio publico. Acesso
/// a inventario de uma rede de ensino e concedido, nao solicitado. Com o
/// painel publicado em endereco publico, um botao de criar conta permitiria
/// que qualquer pessoa com o link visse todo o parque de equipamentos.
///
/// A recuperacao de senha continua disponivel: quem ja tem conta consegue
/// redefinir sozinho, sem depender do administrador.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _chaveForm = GlobalKey<FormState>();

  bool _carregando = false;
  bool _senhaVisivel = false;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_chaveForm.currentState!.validate()) return;

    setState(() {
      _carregando = true;
      _erro = null;
      _aviso = null;
    });

    try {
      await _auth.entrar(_email.text, _senha.text);
      // Nao e preciso navegar: o AuthGate no main.dart percebe a mudanca
      // de estado e troca a tela sozinho.
    } catch (e) {
      if (mounted) setState(() => _erro = AuthService.traduzirErro(e));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _recuperarSenha() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _erro = 'Informe o e-mail para receber o link.');
      return;
    }
    try {
      await _auth.recuperarSenha(email);
      if (mounted) {
        setState(() {
          _erro = null;
          _aviso = 'Se houver conta para $email, o link de redefinicao '
              'foi enviado.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = AuthService.traduzirErro(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _chaveForm,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.storage_rounded,
                      size: 56, color: tema.colorScheme.primary),
                  const SizedBox(height: 18),
                  Text('Inventario Preditivo',
                      textAlign: TextAlign.center,
                      style: tema.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Bancada de Validacao Fisica - URE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: tema.colorScheme.outline)),
                  const SizedBox(height: 32),

                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Informe o e-mail';
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'E-mail invalido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _senha,
                    obscureText: !_senhaVisivel,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_senhaVisivel
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                        onPressed: () =>
                            setState(() => _senhaVisivel = !_senhaVisivel),
                      ),
                    ),
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Informe a senha' : null,
                  ),

                  if (_erro != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tema.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            size: 19, color: tema.colorScheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_erro!,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: tema.colorScheme.onErrorContainer)),
                        ),
                      ]),
                    ),
                  ],

                  if (_aviso != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E9E5B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline,
                            size: 19, color: Color(0xFF2E9E5B)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_aviso!,
                              style: const TextStyle(
                                  fontSize: 12.5, color: Color(0xFF2E9E5B))),
                        ),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 22),

                  FilledButton(
                    onPressed: _carregando ? null : _entrar,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _carregando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Text('Entrar'),
                  ),

                  const SizedBox(height: 8),

                  TextButton(
                    onPressed: _carregando ? null : _recuperarSenha,
                    child: const Text('Esqueci minha senha'),
                  ),

                  const SizedBox(height: 20),
                  Text(
                    'O acesso e concedido pelo administrador do sistema.\n'
                    'Solicite seu cadastro a equipe responsavel pela URE.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11.5, color: tema.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}