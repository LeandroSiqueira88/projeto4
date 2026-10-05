import 'package:flutter_test/flutter_test.dart';
import 'package:bancada_app/models/maquina.dart';
import 'package:bancada_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  group('Inventario & Predicao - Testes Unitarios (Univesp PI)', () {
    test('1. Deserializacao completa com sucesso (Maquina.fromMap)', () {
      final data = {
        'numero_serie': 'ABC123XYZ',
        'tipo_identificador': 'SERIAL_BIOS',
        'hostname': 'PC-LAB-01',
        'fabricante': 'Dell Inc.',
        'modelo': 'OptiPlex 3050',
        'cie': '999001',
        'ure_diretoria': 'RIBEIRAO PRETO',
        'escola_nome': 'EE Prof. Joao',
        'ambiente': 'Lab 01',
        'categoria_equipamento': 'Desktop',
        'processador': 'Intel Core i5',
        'cpu_cores': 4,
        'memoria_ram_gb': 8.0,
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
        'status_equipamento': 'Disponível',
        'avaliacao_tecnica': 'Bom',
        'data_visita': '2023-10-01T10:00:00Z',
        'tecnico_responsavel': 'Elias Sousa',
        'status_visita': 'Concluída',
        'mac_address': '00:1A:2B:3C:4D:5E',
      };

      final maquina = Maquina.fromMap('ABC123XYZ', data);

      expect(maquina.numeroSerie, 'ABC123XYZ');
      expect(maquina.hostname, 'PC-LAB-01');
      expect(maquina.fabricante, 'Dell Inc.');
      expect(maquina.modelo, 'OptiPlex 3050');
      expect(maquina.cie, '999001');
      expect(maquina.ureDiretoria, 'RIBEIRAO PRETO');
      expect(maquina.escolaNome, 'EE Prof. Joao');
      expect(maquina.ambiente, 'Lab 01');
      expect(maquina.processador, 'Intel Core i5');
      expect(maquina.cpuCores, 4);
      expect(maquina.memoriaRamGb, 8.0);
      expect(maquina.ramPentes, 1);
      expect(maquina.modeloDisco, 'ST500DM002');
      // 500107862000 bytes / 1e9 = 500.1 GB
      expect(maquina.capacidadeDiscoGb, closeTo(500.1, 0.1));
      expect(maquina.riscoFalha, 0.15);
      expect(maquina.faixa, FaixaRisco.ok);
      expect(maquina.ativa, true);
      expect(maquina.macAddress, '00:1A:2B:3C:4D:5E');
      expect(maquina.tecnicoResponsavel, 'Elias Sousa');
      expect(maquina.smart['smart_5_raw'], 0);
    });

    test('2. Resiliencia e mapeamento de campos legados', () {
      final dataLegado = {
        'serial_bios': 'OLD_SERIAL',
        'modelo_pc': 'Old Model',
        'escola': 'Old School',
        'sala': 'Old Sala',
        'cpu': 'Old CPU',
        'ram_gb': 4.0,
        'status': 'quarentena',
        'atualizado_em': '2023-01-01T10:00:00Z',
      };

      final maquina = Maquina.fromMap('LEGACY_ID', dataLegado);

      expect(maquina.numeroSerie, 'OLD_SERIAL');
      expect(maquina.modelo, 'Old Model');
      expect(maquina.escolaNome, 'Old School');
      expect(maquina.ambiente, 'Old Sala');
      expect(maquina.processador, 'Old CPU');
      expect(maquina.memoriaRamGb, 4.0);
      expect(maquina.emQuarentena, true);
      expect(maquina.dataVisita, isNotNull);
    });

    test('3. Teste de conversoes de tipo robustas (_toInt, _toDouble, _toDateTime)', () {
      final map = {
        'numero_serie': 'TEST',
        'cpu_cores': 8.5,
        'risco_falha': 42,
        'data_visita': '2023-05-10T10:00:00Z',
      };

      final m = Maquina.fromMap('TEST', map);
      expect(m.cpuCores, 8);
      expect(m.riscoFalha, 42.0);
      expect(m.dataVisita, isA<DateTime>());
      expect(m.dataVisita?.year, 2023);
    });

    test('4. Classificacao precisa de Faixas de Risco e Textos', () {
      final mOk = Maquina(numeroSerie: '1', riscoFalha: 0.10);
      final mAtencao = Maquina(numeroSerie: '2', riscoFalha: 0.40);
      final mCritico = Maquina(numeroSerie: '3', riscoFalha: 0.85);
      final mSemDados = Maquina(numeroSerie: '4', riscoFalha: null);

      expect(mOk.faixa, FaixaRisco.ok);
      expect(mOk.riscoTexto, '10.0%');

      expect(mAtencao.faixa, FaixaRisco.atencao);
      expect(mAtencao.riscoTexto, '40.0%');

      expect(mCritico.faixa, FaixaRisco.critico);
      expect(mCritico.riscoTexto, '85.0%');

      expect(mSemDados.faixa, FaixaRisco.semDados);
      expect(mSemDados.riscoTexto, '--');
    });

    test('5. Traducao de Erros do Firebase Auth para UX', () {
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

    group('Filtros de Interface (Simulacao de Logica)', () {
      test('Busca por Serial, Escola ou CIE', () {
        final m = Maquina(
          numeroSerie: 'ABC123',
          cie: '999001',
          escolaNome: 'EE Francisco Ferreira',
          ambiente: 'Lab',
        );

        bool passa(String busca) {
          final termo = busca.toLowerCase();
          final alvos = '${m.numeroSerie} ${m.escolaNome} ${m.cie}'.toLowerCase();
          return alvos.contains(termo);
        }

        expect(passa('ABC'), isTrue);
        expect(passa('999'), isTrue);
        expect(passa('Francisco'), isTrue);
        expect(passa('XYZ'), isFalse);
      });
    });
  });

}
