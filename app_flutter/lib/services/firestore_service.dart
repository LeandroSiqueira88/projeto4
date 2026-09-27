import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/maquina.dart';

/// Camada unica de acesso ao Firestore com tratamento de erros,
/// resiliencia e suporte a operacoes offline.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _usuario => FirebaseAuth.instance.currentUser?.email ?? 'desconhecido';
  String get _agora => DateTime.now().toUtc().toIso8601String();

  // -------------------------------------------------------------------------
  // Leitura com tratamento de erros e resiliencia de Stream
  // -------------------------------------------------------------------------

  /// Todas as maquinas, em tempo real - inclusive as baixadas.
  Stream<List<Maquina>> maquinas() {
    return _db
        .collection('maquinas')
        .orderBy('atualizado_em', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Maquina.fromMap(d.id, d.data())).toList())
        .handleError((error) {
      print('Erro ao carregar stream de maquinas: $error');
      throw _tratarErroFirestore(error);
    });
  }

  /// Uma maquina especifica, em tempo real.
  Stream<Maquina?> maquina(String serial) {
    return _db
        .collection('maquinas')
        .doc(serial)
        .snapshots()
        .map((d) => d.exists && d.data() != null ? Maquina.fromMap(d.id, d.data()!) : null)
        .handleError((error) {
      print('Erro ao carregar maquina $serial: $error');
      throw _tratarErroFirestore(error);
    });
  }

  Stream<List<Maquina>> quarentena() {
    return _db
        .collection('maquinas')
        .where('status', isEqualTo: 'quarentena')
        .snapshots()
        .map((s) => s.docs.map((d) => Maquina.fromMap(d.id, d.data())).toList())
        .handleError((error) {
      print('Erro ao carregar quarentena: $error');
      throw _tratarErroFirestore(error);
    });
  }

  Stream<List<Map<String, dynamic>>> historico(String serial) {
    return _db
        .collection('maquinas')
        .doc(serial)
        .collection('leituras')
        .orderBy('atualizado_em')
        .limitToLast(60)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList())
        .handleError((error) {
      print('Erro ao carregar historico de $serial: $error');
      throw _tratarErroFirestore(error);
    });
  }

  Stream<List<Map<String, dynamic>>> eventos({int limite = 50}) {
    return _db
        .collection('eventos')
        .orderBy('criado_em', descending: true)
        .limit(limite)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList())
        .handleError((error) {
      print('Erro ao carregar eventos: $error');
      throw _tratarErroFirestore(error);
    });
  }

  // -------------------------------------------------------------------------
  // Gestao com Try-Catch e Tratamento de Excecoes
  // -------------------------------------------------------------------------

  Future<void> _registrarEvento(String tipo, String serial, String descricao,
      [Map<String, dynamic>? extra]) async {
    try {
      await _db.collection('eventos').add({
        'tipo': tipo,
        'serial_bios': serial,
        'descricao': descricao,
        'usuario': _usuario,
        'criado_em': _agora,
        'origem': 'aplicativo',
        ...?extra,
      });
    } catch (e) {
      print('Aviso: Falha ao registrar evento ($tipo): $e');
    }
  }

  Exception _tratarErroFirestore(dynamic e) {
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
        case 'unavailable':
        case 'network-request-failed':
          return Exception('Erro de conexão ou permissão negada (Firebase 403/offline). Verifique sua rede e permissões.');
        default:
          return Exception('Erro no Firestore (${e.code}): ${e.message}');
      }
    }
    return Exception('Ocorreu um erro inesperado: $e');
  }

  /// Tira a maquina da quarentena e atribui a uma escola/sala.
  Future<void> aprovarMaquina(String serial, String escola, String sala) async {
    try {
      await _db.collection('maquinas').doc(serial).update({
        'status': 'ativo',
        'escola': escola,
        'sala': sala,
      });
      await _registrarEvento(
          'cadastro', serial, 'Maquina cadastrada em $escola - $sala');
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }

  /// Altera escola e sala de uma maquina ja cadastrada, sem mexer no status.
  Future<void> atualizarLocalizacao(
      String serial, String escola, String sala) async {
    try {
      await _db.collection('maquinas').doc(serial).update({
        'escola': escola,
        'sala': sala,
      });
      await _registrarEvento(
          'remanejamento', serial, 'Movida para $escola - $sala');
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }

  /// BAIXA DE PATRIMONIO (exclusao logica).
  Future<void> darBaixa(String serial, String motivo,
      {String observacao = ''}) async {
    try {
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
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }

  /// Desfaz a baixa e devolve a maquina ao inventario ativo.
  Future<void> reativar(String serial) async {
    try {
      await _db.collection('maquinas').doc(serial).update({
        'status': 'ativo',
        'motivo_baixa': '',
        'data_baixa': '',
        'usuario_baixa': '',
      });
      await _registrarEvento(
          'reativacao', serial, 'Baixa revertida, maquina reativada');
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }

  /// Devolve a maquina para a quarentena.
  Future<void> devolverParaQuarentena(String serial) async {
    try {
      await _db.collection('maquinas').doc(serial).update({
        'status': 'quarentena',
        'escola': '',
        'sala': '',
      });
      await _registrarEvento(
          'quarentena', serial, 'Devolvida para quarentena');
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }

  /// EXCLUSAO DEFINITIVA.
  Future<void> excluirDefinitivo(String serial, String motivo) async {
    try {
      await _registrarEvento('exclusao', serial,
          'Exclusao definitiva do registro: $motivo', {'motivo': motivo});

      final leituras = _db.collection('maquinas').doc(serial).collection('leituras');

      // Apaga em lotes de 400.
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
    } catch (e) {
      throw _tratarErroFirestore(e);
    }
  }
}
