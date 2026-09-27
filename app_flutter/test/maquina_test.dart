import 'package:flutter_test/flutter_test.dart';
import 'package:bancada_app/models/maquina.dart';
import 'package:bancada_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  group('Inventario & Predicao - Testes Unitarios (Univesp PI)', () {
    test('1. Deserializacao completa com sucesso (Maquina.fromMap)', () {
      final data = {
        'serial_bios': 'ABC123XYZ',
        'tipo_identificador': 'BIOS',
        'hostname': 'PC-LAB-01',
        'fabricante': 'Dell Inc.',
        'modelo_pc': 'OptiPlex 3050',
        'escola': 'EE Prof. Joao',
        'sala': 'Lab 01',
        'processador': 'Intel Core i5',
        'cpu_cores': 4,
        'memoria_ram_gb': 8,
        'ram_pentes': 1,
        'disco': {
          'model': 'ST500DM002',
          'tipo_disco': 'HDD',
          'capacity_bytes': 500107862000,
          'smart_ok': true,
          'smart_5_raw': 0,
          'smart_187_raw': 0,
        },
        'risco_falha': 0.15,
        'status_validacao': 'ativo',
        'data_registro': '2023-10-01T10:00:00Z',
      };

      final maquina = Maquina.fromMap('ABC123XYZ', data);

      expect(maquina.serialBios, 'ABC123XYZ');
      expect(maquina.hostname, 'PC-LAB-01');
      expect(maquina.fabricante, 'Dell Inc.');
      expect(maquina.escola, 'EE Prof. Joao');
      expect(maquina.sala, 'Lab 01');
      expect(maquina.cpuCores, 4);
      expect(maquina.ramGb, 8);
      expect(maquina.modeloDisco, 'ST500DM002');
      expect(maquina.capacidadeBytes, 500107862000);
      expect(maquina.riscoFalha, 0.15);
      expect(maquina.faixa, FaixaRisco.ok);
      expect(maquina.ativa, true);
      expect(maquina.smart['smart_5_raw'], 0);
    });

    test('2. Resiliencia contra valores nulos, vazios e OEM (Default string)', () {
      final dataMalformado = {
        'serial_bios': null,
        'hostname': 'Default string',
        'fabricante': '',
        'cpu_cores': 'invalido',
        'memoria_ram_gb': null,
        'disco': null,
        'risco_falha': '0.75',
        'status_validacao': null,
      };

      final maquina = Maquina.fromMap('FALLBACK_ID', dataMalformado);

      expect(maquina.serialBios, 'FALLBACK_ID');
      expect(maquina.hostname, 'Default string');
      expect(maquina.fabricante, '');
      expect(maquina.cpuCores, 0);
      expect(maquina.ramGb, 0);
      expect(maquina.modeloDisco, '');
      expect(maquina.capacidadeBytes, 0);
      expect(maquina.riscoFalha, 0.75);
      expect(maquina.faixa, FaixaRisco.critico);
      expect(maquina.status, 'ativo');
      expect(maquina.smart, isEmpty);
    });

    test('3. Teste de conversoes de tipo robustas (_toInt, _toDouble, _toDateTime)', () {
      final map = {
        'serial_bios': 'TEST',
        'cpu_cores': 8.5,
        'risco_falha': 42,
        'data_registro': DateTime(2023, 5, 10),
      };

      final m = Maquina.fromMap('TEST', map);
      expect(m.cpuCores, 8);
      expect(m.riscoFalha, 42.0);
      expect(m.atualizadoEm, DateTime(2023, 5, 10));
    });

    test('4. Classificacao precisa de Faixas de Risco e Textos', () {
      final mOk = Maquina(serialBios: '1', riscoFalha: 0.10);
      final mAtencao = Maquina(serialBios: '2', riscoFalha: 0.40);
      final mCritico = Maquina(serialBios: '3', riscoFalha: 0.85);
      final mSemDados = Maquina(serialBios: '4', riscoFalha: null);

      expect(mOk.faixa, FaixaRisco.ok);
      expect(mOk.riscoTexto, '10.0%');

      expect(mAtencao.faixa, FaixaRisco.atencao);
      expect(mAtencao.riscoTexto, '40.0%');

      expect(mCritico.faixa, FaixaRisco.critico);
      expect(mCritico.riscoTexto, '85.0%');

      expect(mSemDados.faixa, FaixaRisco.semDados);
      expect(mSemDados.riscoTexto, '--');
    });

    test('5. Traducao de Erros do Firebase Auth para LGPD/UX', () {
      expect(
        AuthService.traduzirErro(
          FirebaseAuthException(code: 'user-not-found', message: 'Not found'),
        ),
        'Nao existe conta com esse e-mail.',
      );

      expect(
        AuthService.traduzirErro(
          FirebaseAuthException(code: 'wrong-password', message: 'Wrong password'),
        ),
        'Senha incorreta.',
      );

      expect(
        AuthService.traduzirErro(Exception('Erro genérico')),
        'Nao foi possivel conectar. Verifique sua internet.',
      );
    });
  });
}
