import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/maquina.dart';

/// Camada unica de acesso ao Firestore.
/// Nenhuma tela fala com o Firestore direto - facilita testar e trocar de backend.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _usuario => FirebaseAuth.instance.currentUser?.email ?? 'desconhecido';
  String get _agora => DateTime.now().toUtc().toIso8601String();

  // -------------------------------------------------------------------------
  // Leitura
  // -------------------------------------------------------------------------

  /// Todas as maquinas, em tempo real - inclusive as baixadas.
  /// As telas filtram conforme o contexto.
  Stream<List<Maquina>> maquinas() {
    return _db
        .collection('maquinas')
        .orderBy('atualizado_em', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Maquina.fromMap(d.id, d.data())).toList());
  }

  /// Uma maquina especifica, em tempo real.
  ///
  /// A ficha usa este stream em vez do objeto recebido por parametro. Assim,
  /// quando o usuario edita a localizacao ou da baixa, a tela se atualiza
  /// sozinha - sem precisar voltar para a lista e entrar de novo.
  Stream<Maquina?> maquina(String serial) {
    return _db.collection('maquinas').doc(serial).snapshots().map(
        (d) => d.exists ? Maquina.fromMap(d.id, d.data()!) : null);
  }

  Stream<List<Maquina>> quarentena() {
    return _db
        .collection('maquinas')
        .where('status', isEqualTo: 'quarentena')
        .snapshots()
        .map((s) => s.docs.map((d) => Maquina.fromMap(d.id, d.data())).toList());
  }

  Stream<List<Map<String, dynamic>>> historico(String serial) {
    return _db
        .collection('maquinas')
        .doc(serial)
        .collection('leituras')
        .orderBy('atualizado_em')
        .limitToLast(60)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> eventos({int limite = 50}) {
    return _db
        .collection('eventos')
        .orderBy('criado_em', descending: true)
        .limit(limite)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // -------------------------------------------------------------------------
  // Gestao
  // -------------------------------------------------------------------------

  Future<void> _registrarEvento(String tipo, String serial, String descricao,
      [Map<String, dynamic>? extra]) {
    return _db.collection('eventos').add({
      'tipo': tipo,
      'serial_bios': serial,
      'descricao': descricao,
      'usuario': _usuario,
      'criado_em': _agora,
      'origem': 'aplicativo',
      ...?extra,
    });
  }

  /// Tira a maquina da quarentena e atribui a uma escola/sala.
  Future<void> aprovarMaquina(String serial, String escola, String sala) async {
    await _db.collection('maquinas').doc(serial).update({
      'status': 'ativo',
      'escola': escola,
      'sala': sala,
    });
    await _registrarEvento(
        'cadastro', serial, 'Maquina cadastrada em $escola - $sala');
  }

  /// Altera escola e sala de uma maquina ja cadastrada, sem mexer no status.
  Future<void> atualizarLocalizacao(
      String serial, String escola, String sala) async {
    await _db.collection('maquinas').doc(serial).update({
      'escola': escola,
      'sala': sala,
    });
    await _registrarEvento(
        'remanejamento', serial, 'Movida para $escola - $sala');
  }

  /// BAIXA DE PATRIMONIO (exclusao logica).
  ///
  /// A maquina sai do inventario ativo mas o documento e todo o historico de
  /// leituras permanecem no banco. E o caminho recomendado: preserva o rastro
  /// para auditoria e mantem os dados disponiveis para retreinar o modelo.
  ///
  /// Reversivel por `reativar`.
  Future<void> darBaixa(String serial, String motivo,
      {String observacao = ''}) async {
    final descricao =
        observacao.isEmpty ? motivo : '$motivo - $observacao';

    await _db.collection('maquinas').doc(serial).update({
      'status': 'descartado',
      'motivo_baixa': descricao,
      'data_baixa': _agora,
      'usuario_baixa': _usuario,
    });

    await _registrarEvento('baixa', serial, 'Baixa: $descricao',
        {'motivo': motivo});
  }

  /// Desfaz a baixa e devolve a maquina ao inventario ativo.
  Future<void> reativar(String serial) async {
    await _db.collection('maquinas').doc(serial).update({
      'status': 'ativo',
      'motivo_baixa': '',
      'data_baixa': '',
      'usuario_baixa': '',
    });
    await _registrarEvento(
        'reativacao', serial, 'Baixa revertida, maquina reativada');
  }

  /// Devolve a maquina para a quarentena.
  /// Util quando o tecnico percebe que cadastrou no lugar errado.
  Future<void> devolverParaQuarentena(String serial) async {
    await _db.collection('maquinas').doc(serial).update({
      'status': 'quarentena',
      'escola': '',
      'sala': '',
    });
    await _registrarEvento(
        'quarentena', serial, 'Devolvida para quarentena');
  }

  /// EXCLUSAO DEFINITIVA.
  ///
  /// Apaga o documento e todo o historico de leituras. NAO TEM VOLTA.
  ///
  /// Use apenas para registro duplicado, maquina cadastrada por engano ou
  /// equipamento que nunca existiu no parque. Para equipamento real que saiu
  /// de uso, a baixa e o caminho correto.
  ///
  /// O Firestore nao remove subcolecoes ao apagar o documento pai - o
  /// historico ficaria orfao, ocupando espaco e invisivel. Por isso as
  /// leituras sao apagadas em lotes antes do documento.
  ///
  /// O evento de exclusao e registrado ANTES de apagar, para que o rastro
  /// sobreviva a operacao.
  Future<void> excluirDefinitivo(String serial, String motivo) async {
    await _registrarEvento('exclusao', serial,
        'Exclusao definitiva do registro: $motivo', {'motivo': motivo});

    final leituras = _db.collection('maquinas').doc(serial).collection('leituras');

    // Apaga em lotes de 400 (o limite do Firestore e 500 operacoes por lote).
    while (true) {
      final pagina = await leituras.limit(400).get();
      if (pagina.docs.isEmpty) break;

      final lote = _db.batch();
      for (final doc in pagina.docs) {
        lote.delete(doc.reference);
      }
      await lote.commit();

      if (pagina.docs.length < 400) break;
    }

    await _db.collection('maquinas').doc(serial).delete();
  }
}
