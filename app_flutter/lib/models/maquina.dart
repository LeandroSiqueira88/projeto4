/// Modelo de dados de uma maquina do inventario.
/// Alinhado ao padrao URE/FDE.
library;

enum FaixaRisco { ok, atencao, critico, semDados }

class Maquina {
  final String numeroSerie;           // ID Principal (Serial ou UUID)
  final String tipoIdentificador;     // SERIAL_BIOS ou UUID_SISTEMA
  final String hostname;
  final String fabricante;
  final String modelo;                // Modelo do PC
  final String cie;
  final String ureDiretoria;
  final String escolaNome;            // Nome da Escola
  final String ambiente;              // Local/Sala (Ambiente)
  final String categoriaEquipamento;  // Ex: Desktop, Laptop
  final String processador;           // CPU
  final double memoriaRamGb;          // RAM
  final String statusEquipamento;     // Disponivel, Indisponivel, Descartado
  final String avaliacaoTecnica;      // Bom, Regular, Ruim, Defeituoso
  final DateTime? dataVisita;         // Data da última coleta
  final String tecnicoResponsavel;
  final String statusVisita;          // Concluida, Quarentena

  // Detalhes de Hardware adicionais
  final int cpuCores;
  final int ramPentes;
  final String modeloDisco;
  final String tipoDisco;
  final double capacidadeDiscoGb;
  final String macAddress;

  // Dados de Baixa
  final String motivoBaixa;
  final DateTime? dataBaixa;
  final String usuarioBaixa;
  final String observacoes;
  
  final double? riscoFalha;
  final Map<String, dynamic> smart;

  Maquina({
    required this.numeroSerie,
    this.tipoIdentificador = 'SERIAL_BIOS',
    this.hostname = '',
    this.fabricante = '',
    this.modelo = '',
    this.cie = '',
    this.ureDiretoria = '',
    this.escolaNome = '',
    this.ambiente = '',
    this.categoriaEquipamento = 'Desktop',
    this.processador = '',
    this.memoriaRamGb = 0.0,
    this.statusEquipamento = 'Disponível',
    this.avaliacaoTecnica = 'Bom',
    this.dataVisita,
    this.tecnicoResponsavel = '',
    this.statusVisita = 'Concluída',
    this.cpuCores = 0,
    this.ramPentes = 0,
    this.modeloDisco = '',
    this.tipoDisco = '',
    this.capacidadeDiscoGb = 0.0,
    this.macAddress = '',
    this.motivoBaixa = '',
    this.dataBaixa,
    this.usuarioBaixa = '',
    this.observacoes = '',
    this.riscoFalha,
    this.smart = const {},
  });

  static int _toInt(dynamic val, [int padrao = 0]) {
    if (val == null) return padrao;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? padrao;
    return padrao;
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
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
    final disco = m['disco'] is Map ? m['disco'] : {};
    
    return Maquina(
      numeroSerie: (m['numero_serie'] ?? m['id_dispositivo'] ?? m['serial_bios'] ?? id).toString(),
      tipoIdentificador: (m['tipo_identificador'] ?? m['origem_serial'] ?? 'SERIAL_BIOS').toString(),
      hostname: (m['hostname'] ?? '').toString(),
      fabricante: (m['fabricante'] ?? '').toString(),
      modelo: (m['modelo'] ?? m['modelo_pc'] ?? '').toString(),
      cie: (m['cie'] ?? '').toString(),
      ureDiretoria: (m['ure_diretoria'] ?? m['ure'] ?? '').toString(),
      escolaNome: (m['escola_nome'] ?? m['escola'] ?? '').toString(),
      ambiente: (m['ambiente'] ?? m['sala'] ?? '').toString(),
      categoriaEquipamento: (m['categoria_equipamento'] ?? 'Desktop').toString(),
      processador: (m['processador'] ?? m['cpu'] ?? '').toString(),
      memoriaRamGb: _toDouble(m['memoria_ram_gb'] ?? m['ram_gb']),
      statusEquipamento: (m['status_equipamento'] ?? m['status_validacao'] ?? m['status'] ?? 'Disponível').toString(),
      avaliacaoTecnica: (m['avaliacao_tecnica'] ?? m['avaliacao'] ?? 'Bom').toString(),
      dataVisita: _toDateTime(m['data_visita'] ?? m['atualizado_em'] ?? m['data_registro']),
      tecnicoResponsavel: (m['tecnico_responsavel'] ?? m['operador'] ?? '').toString(),
      statusVisita: (m['status_visita'] ?? 'Concluída').toString(),
      
      cpuCores: _toInt(m['cpu_cores']),
      ramPentes: _toInt(m['ram_pentes']),
      modeloDisco: (m['modelo_disco'] ?? disco['model'] ?? '').toString(),
      tipoDisco: (m['tipo_disco'] ?? disco['tipo_disco'] ?? '').toString(),
      capacidadeDiscoGb: _toDouble(m['capacidade_disco_gb'] ?? (disco['capacity_bytes'] != null ? (disco['capacity_bytes'] / 1e9) : 0)),
      macAddress: (m['mac_address'] ?? '').toString(),

      motivoBaixa: (m['motivo_baixa'] ?? '').toString(),
      dataBaixa: _toDateTime(m['data_baixa']),
      usuarioBaixa: (m['usuario_baixa'] ?? '').toString(),
      observacoes: (m['observacoes'] ?? '').toString(),

      riscoFalha: m['risco_falha'] != null ? _toDouble(m['risco_falha']) : null,
      smart: (m['smart'] as Map<String, dynamic>?) ?? (disco is Map && disco.entries.any((e) => e.key.startsWith('smart_')) ? 
          {for (var e in disco.entries) if (e.key.startsWith('smart_')) e.key: e.value} : const {}),
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

  bool get emQuarentena => statusVisita == 'Quarentena' || statusEquipamento.toLowerCase() == 'quarentena';
  bool get baixada => statusEquipamento.toLowerCase() == 'descartado' || statusEquipamento.toLowerCase() == 'baixado';
  bool get ativa => !emQuarentena && !baixada;

  String get escolaTexto => escolaNome.isEmpty ? 'Não atribuída' : escolaNome;
  String get ambienteTexto => ambiente.isEmpty ? '-' : ambiente;

  String get statusTexto => switch (statusEquipamento.toLowerCase()) {
    'disponível' => 'Ativo',
    'indisponível' => 'Indisponível',
    'quarentena' => 'Quarentena',
    'descartado' || 'baixado' => 'Baixado',
    _ => statusEquipamento,
  };

  String get capacidadeTexto => capacidadeDiscoGb == 0
      ? '--'
      : '${capacidadeDiscoGb.toStringAsFixed(0)} GB';

  String get identificadorExibicao => numeroSerie.startsWith('UUID:') 
      ? '${numeroSerie.substring(5, 13)}...'
      : numeroSerie;
}

class MotivosBaixa {
  static const lista = [
    'Defeito irreparável',
    'Obsolescência',
    'Furto ou extravio',
    'Transferência para outra unidade',
    'Doação',
    'Sinistro (incêndio, alagamento)',
    'Outro',
  ];
}
