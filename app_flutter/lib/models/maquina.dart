
/// Modelo de dados de uma maquina do inventario.
/// Espelha o documento gravado em `maquinas/{serial_bios}` no Firestore
/// pelo script bancada/main.py.

enum FaixaRisco { ok, atencao, critico, semDados }

class Maquina {
  final String serialBios;       // id_dispositivo
  final String tipoIdentificador;// tipo_identificador (BIOS, placa-mae, disco, UUID)
  final String hostname;         // hostname
  final String fabricante;
  final String modeloPc;
  final String escola;
  final String sala;
  final String cpu;              // processador
  final int cpuCores;
  final int ramGb;               // memoria_ram_gb
  final int ramPentes;
  final String modeloDisco;
  final String tipoDisco;
  final int capacidadeBytes;
  final double? riscoFalha;
  final String status;           // status_validacao (ativo | quarentena | descartado)
  final DateTime? atualizadoEm;   // data_registro
  final Map<String, dynamic> smart;

  // ---- dados de baixa de patrimonio ----
  final String motivoBaixa;
  final DateTime? dataBaixa;
  final String usuarioBaixa;

  Maquina({
    required this.serialBios,
    this.tipoIdentificador = 'BIOS',
    this.hostname = '',
    this.fabricante = '',
    this.modeloPc = '',
    this.escola = '',
    this.sala = '',
    this.cpu = '',
    this.cpuCores = 0,
    this.ramGb = 0,
    this.ramPentes = 0,
    this.modeloDisco = '',
    this.tipoDisco = '',
    this.capacidadeBytes = 0,
    this.riscoFalha,
    this.status = 'ativo',
    this.atualizadoEm,
    this.smart = const {},
    this.motivoBaixa = '',
    this.dataBaixa,
    this.usuarioBaixa = '',
  });

  // Parsers robustos para prevenção de TypeError
  static int _toInt(dynamic val, [int padrao = 0]) {
    if (val == null) return padrao;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? padrao;
    return padrao;
  }

  static double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  static DateTime? _toDateTime(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    try {
      return (val as dynamic).toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }

  factory Maquina.fromMap(String id, Map<String, dynamic> m) {
    final disco = (m['disco'] as Map<String, dynamic>?) ?? const {};

    // Mapeamento tolerante que aceita nomes do relatório e do código Python
    final idDispositivo = m['id_dispositivo'] ?? m['serial_bios'] ?? id;
    final tipoIdent = m['tipo_identificador'] ?? m['origem_serial'] ?? 'BIOS';
    final host = m['hostname'] ?? m['nome_host'] ?? '';
    final proc = m['processador'] ?? m['cpu'] ?? '';
    final ram = m['memoria_ram_gb'] ?? m['ram_gb'] ?? 0;
    final statusVal = m['status_validacao'] ?? m['status'] ?? 'ativo';
    final dataReg = m['data_registro'] ?? m['atualizado_em'];

    return Maquina(
      serialBios: '$idDispositivo',
      tipoIdentificador: '$tipoIdent',
      hostname: '$host',
      fabricante: (m['fabricante'] ?? '') as String,
      modeloPc: (m['modelo_pc'] ?? '') as String,
      escola: (m['escola'] ?? '') as String,
      sala: (m['sala'] ?? '') as String,
      cpu: '$proc',
      cpuCores: _toInt(m['cpu_cores']),
      ramGb: _toInt(ram),
      ramPentes: _toInt(m['ram_pentes']),
      modeloDisco: (disco['model'] ?? '') as String,
      tipoDisco: (disco['tipo_disco'] ?? '') as String,
      capacidadeBytes: _toInt(disco['capacity_bytes']),
      riscoFalha: _toDouble(m['risco_falha']),
      status: '$statusVal',
      atualizadoEm: _toDateTime(dataReg),
      smart: {
        for (final e in disco.entries)
          if (e.key.startsWith('smart_') && e.key != 'smart_ok')
            e.key: e.value,
      },
      motivoBaixa: (m['motivo_baixa'] ?? '') as String,
      dataBaixa: _toDateTime(m['data_baixa']),
      usuarioBaixa: (m['usuario_baixa'] ?? '') as String,
    );
  }

  FaixaRisco get faixa {
    if (riscoFalha == null) return FaixaRisco.semDados;
    if (riscoFalha! >= 0.60) return FaixaRisco.critico;
    if (riscoFalha! >= 0.25) return FaixaRisco.atencao;
    return FaixaRisco.ok;
  }

  String get riscoTexto =>
      riscoFalha == null ? '--' : '${(riscoFalha! * 100).toStringAsFixed(1)}%';

  String get capacidadeTexto => capacidadeBytes == 0
      ? '--'
      : '${(capacidadeBytes / 1e9).toStringAsFixed(0)} GB';

  bool get emQuarentena => status == 'quarentena';
  bool get baixada => status == 'descartado';

  /// Maquina que conta no inventario ativo da rede.
  bool get ativa => status == 'ativo';

  String get escolaTexto => escola.isEmpty ? 'Nao atribuida' : escola;
  String get salaTexto => sala.isEmpty ? '-' : sala;

  String get statusTexto => switch (status) {
        'ativo' => 'Ativo',
        'quarentena' => 'Quarentena',
        'descartado' => 'Baixado',
        _ => status,
      };
}

/// Motivos previstos para baixa de patrimonio.
/// Lista fechada para que o relatorio consolidado seja agrupavel - texto
/// livre viraria dezenas de variacoes da mesma coisa.
class MotivosBaixa {
  static const lista = [
    'Defeito irreparavel',
    'Obsolescencia',
    'Furto ou extravio',
    'Transferencia para outra unidade',
    'Doacao',
    'Sinistro (incendio, alagamento)',
    'Outro',
  ];
}
