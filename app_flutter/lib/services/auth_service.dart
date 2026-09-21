import 'package:firebase_auth/firebase_auth.dart';

/// Camada unica de autenticacao.
/// Nenhuma tela chama o FirebaseAuth direto - facilita testar e trocar depois.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Emite o usuario atual sempre que o estado de login muda.
  /// E o que o AuthGate no main.dart escuta.
  Stream<User?> get mudancasDeEstado => _auth.authStateChanges();

  User? get usuarioAtual => _auth.currentUser;

  String get emailAtual => _auth.currentUser?.email ?? '';

  Future<UserCredential> entrar(String email, String senha) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: senha,
    );
  }

  Future<UserCredential> criarConta(String email, String senha) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: senha,
    );
  }

  Future<void> recuperarSenha(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sair() => _auth.signOut();

  /// Traduz os codigos de erro do Firebase para mensagens em portugues.
  /// Sem isso o usuario ve coisas como "user-not-found" na tela.
  static String traduzirErro(Object e) {
    if (e is! FirebaseAuthException) {
      return 'Nao foi possivel conectar. Verifique sua internet.';
    }
    return switch (e.code) {
      'invalid-email' => 'E-mail em formato invalido.',
      'user-disabled' => 'Esta conta foi desativada.',
      'user-not-found' => 'Nao existe conta com esse e-mail.',
      'wrong-password' => 'Senha incorreta.',
      'invalid-credential' => 'E-mail ou senha incorretos.',
      'email-already-in-use' => 'Ja existe uma conta com esse e-mail.',
      'weak-password' => 'A senha precisa de pelo menos 6 caracteres.',
            'admin-restricted-operation' =>
        'O cadastro e feito pelo administrador.\n'
            'Solicite seu acesso a equipe da URE.',
      'operation-not-allowed' =>
        'Login por e-mail nao esta habilitado no Firebase.\n'
            'Ative em: Authentication > Sign-in method > Email/Password.',
      'too-many-requests' =>
        'Muitas tentativas. Aguarde alguns minutos e tente de novo.',
      'network-request-failed' => 'Sem conexao com a internet.',
      _ => 'Erro ao autenticar (${e.code}).',
    };
  }
}
