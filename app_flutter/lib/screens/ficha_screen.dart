import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import '../utils/formato.dart';
import '../widgets/dialogo_baixa.dart';
import '../widgets/dialogo_localizacao.dart';
import '../widgets/risco_badge.dart';

const _rotulosSmart = {
  'smart_5_raw': 'Setores realocados',
  'smart_9_raw': 'Horas ligado',
  'smart_12_raw': 'Ciclos de energia',
  'smart_187_raw': 'Erros nao corrigiveis',
  'smart_188_raw': 'Command timeout',
  'smart_194_raw': 'Temperatura (C)',
  'smart_197_raw': 'Setores pendentes',
  'smart_198_raw': 'Setores incorrigiveis',
  'smart_199_raw': 'Erros CRC (cabo)',
};

const _sintomas = {
  'smart_5_raw', 'smart_187_raw', 'smart_197_raw', 'smart_198_raw',
};

class FichaScreen extends StatelessWidget {
  final Maquina maquina;
  const FichaScreen({super.key, required this.maquina});

  @override
  Widget build(BuildContext context) {
    final servico = FirestoreService();

    return StreamBuilder<Maquina?>(
      stream: servico.maquina(maquina.serialBios),
      initialData: maquina,
      builder: (context, snap) {
        // Documento apagado enquanto a tela estava aberta (exclusao
        // definitiva feita aqui ou por outro usuario).
        if (snap.hasData && snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(maquina.serialBios)),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_outline,
                      size: 48, color: Color(0xFF8A8F98)),
                  SizedBox(height: 14),
                  Text('Este registro foi excluido.',
                      style: TextStyle(fontSize: 16)),
                ]),
              ),
            ),
          );
        }
        return _Conteudo(maquina: snap.data ?? maquina, servico: servico);
      },
    );
  }
}

class _Conteudo extends StatelessWidget {
  final Maquina maquina;
  final FirestoreService servico;

  const _Conteudo({required this.maquina, required this.servico});

  void _aviso(BuildContext context, String texto) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _editarLocalizacao(BuildContext context) async {
    final salvou = await abrirDialogoLocalizacao(
      context,
      maquina: maquina,
      cadastrando: maquina.emQuarentena,
    );
    if (salvou && context.mounted) _aviso(context, 'Localizacao atualizada.');
  }

  Future<void> _darBaixa(BuildContext context) async {
    final ok = await abrirDialogoBaixa(context, maquina);
    if (ok && context.mounted) _aviso(context, 'Baixa registrada.');
  }

  Future<void> _reativar(BuildContext context) async {
    await servico.reativar(maquina.serialBios);
    if (context.mounted) _aviso(context, 'Maquina reativada.');
  }

  Future<void> _excluir(BuildContext context) async {
    final ok = await abrirDialogoExclusao(context, maquina);
    if (ok && context.mounted) {
      _aviso(context, 'Registro excluido.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = CoresRisco.de(maquina.faixa);
    final antiga = leituraAntiga(maquina.atualizadoEm);

    return Scaffold(
      appBar: AppBar(
        title: Text(maquina.serialBios),
        actions: [
          if (!maquina.baixada)
            IconButton(
              icon: const Icon(Icons.edit_location_alt_outlined),
              tooltip: 'Alterar localizacao',
              onPressed: () => _editarLocalizacao(context),
            ),
          PopupMenuButton<String>(
            tooltip: 'Mais acoes',
            onSelected: (opcao) {
              switch (opcao) {
                case 'baixa':
                  _darBaixa(context);
                case 'reativar':
                  _reativar(context);
                case 'quarentena':
                  servico.devolverParaQuarentena(maquina.serialBios);
                case 'excluir':
                  _excluir(context);
              }
            },
            itemBuilder: (_) => [
              if (!maquina.baixada)
                const PopupMenuItem(
                  value: 'baixa',
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Dar baixa'),
                    subtitle: Text('Preserva o historico',
                        style: TextStyle(fontSize: 11)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              if (maquina.baixada)
                const PopupMenuItem(
                  value: 'reativar',
                  child: ListTile(
                    leading: Icon(Icons.unarchive_outlined),
                    title: Text('Reativar'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              if (maquina.ativa)
                const PopupMenuItem(
                  value: 'quarentena',
                  child: ListTile(
                    leading: Icon(Icons.help_outline),
                    title: Text('Voltar para quarentena'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'excluir',
                child: ListTile(
                  leading: Icon(Icons.delete_forever_outlined,
                      color: Theme.of(context).colorScheme.error),
                  title: Text('Excluir definitivamente',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                  subtitle: const Text('Apaga tudo, sem volta',
                      style: TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        if (maquina.baixada) _FaixaBaixa(maquina: maquina),

        // ---- medidor de risco ----
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cor.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            Text('Risco de falha do disco em 30 dias',
                style: TextStyle(fontSize: 13, color: cor)),
            const SizedBox(height: 8),
            Text(maquina.riscoTexto,
                style: TextStyle(
                    fontSize: 44, fontWeight: FontWeight.w800, color: cor)),
            Text(CoresRisco.rotulo(maquina.faixa),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: cor)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: maquina.riscoFalha ?? 0,
                minHeight: 9,
                backgroundColor: cor.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(cor),
              ),
            ),
          ]),
        ),

        if (antiga && !maquina.baixada) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CoresRisco.atencao.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: [
              const Icon(Icons.schedule, size: 18, color: CoresRisco.atencao),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ultima leitura ${formatarRelativo(maquina.atualizadoEm)}. '
                  'A predicao pode estar desatualizada.',
                  style: const TextStyle(
                      fontSize: 12.5, color: CoresRisco.atencao),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 24),

        Row(children: [
          const Text('Localizacao',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (!maquina.baixada)
            TextButton.icon(
              onPressed: () => _editarLocalizacao(context),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: Text(maquina.emQuarentena ? 'Cadastrar' : 'Alterar'),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
        ]),
        const SizedBox(height: 8),
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: [
              _Linha(rotulo: 'Escola', valor: maquina.escolaTexto),
              _Linha(rotulo: 'Sala', valor: maquina.salaTexto),
              _Linha(rotulo: 'Status', valor: maquina.statusTexto),
              _Linha(
                rotulo: 'Ultima leitura',
                valor: '${formatarData(maquina.atualizadoEm)}  '
                    '(${formatarRelativo(maquina.atualizadoEm)})',
              ),
            ]),
          ),
        ),

        _Secao(titulo: 'Hardware', linhas: {
          'Fabricante': maquina.fabricante,
          'Modelo': maquina.modeloPc,
          'Processador': maquina.cpu,
          'Nucleos': '${maquina.cpuCores}',
          'Memoria': '${maquina.ramGb} GB em ${maquina.ramPentes} pente(s)',
          'Disco': '${maquina.modeloDisco} ${maquina.capacidadeTexto} '
              '(${maquina.tipoDisco})',
        }),

        _SecaoSmart(smart: maquina.smart),

        const SizedBox(height: 12),
        const Text('Evolucao do risco',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Cada ponto e uma passagem pela bancada',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: servico.historico(maquina.serialBios),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final pontos =
                  snap.data!.where((d) => d['risco_falha'] != null).toList();

              if (pontos.length < 2) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.timeline_outlined,
                        size: 34, color: Color(0xFF8A8F98)),
                    const SizedBox(height: 10),
                    Text(
                      pontos.length == 1
                          ? 'Apenas uma leitura registrada.\n'
                              'O grafico aparece a partir da segunda passagem.'
                          : 'Sem historico registrado ainda.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF8A8F98)),
                    ),
                  ]),
                );
              }

              return _GraficoEvolucao(pontos: pontos, cor: cor);
            },
          ),
        ),
      ]),
    );
  }
}

class _FaixaBaixa extends StatelessWidget {
  final Maquina maquina;
  const _FaixaBaixa({required this.maquina});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF8A8F98).withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF8A8F98).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.archive_outlined, size: 19, color: Color(0xFF8A8F98)),
          SizedBox(width: 9),
          Text('Patrimonio baixado',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF8A8F98))),
        ]),
        const SizedBox(height: 8),
        if (maquina.motivoBaixa.isNotEmpty)
          Text(maquina.motivoBaixa, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '${formatarData(maquina.dataBaixa)}'
          '${maquina.usuarioBaixa.isEmpty ? "" : "  por ${maquina.usuarioBaixa}"}',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A8F98)),
        ),
      ]),
    );
  }
}

class _GraficoEvolucao extends StatelessWidget {
  final List<Map<String, dynamic>> pontos;
  final Color cor;

  const _GraficoEvolucao({required this.pontos, required this.cor});

  @override
  Widget build(BuildContext context) {
    final dados =
        pontos.length > 30 ? pontos.sublist(pontos.length - 30) : pontos;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        minX: 0,
        maxX: (dados.length - 1).toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < dados.length; i++)
                FlSpot(
                    i.toDouble(), (dados[i]['risco_falha'] as num).toDouble()),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            barWidth: 3,
            color: cor,
            dotData: FlDotData(
              show: dados.length <= 15,
              getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                radius: 3.5,
                color: cor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData:
                BarAreaData(show: true, color: cor.withValues(alpha: 0.14)),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: 0.25,
              getTitlesWidget: (valor, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text('${(valor * 100).toInt()}%',
                    style: const TextStyle(
                        fontSize: 10.5, color: Color(0xFF8A8F98))),
              ),
            ),
          ),
        ),
        gridData: const FlGridData(
            show: true, drawVerticalLine: false, horizontalInterval: 0.25),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${(s.y * 100).toStringAsFixed(1)}%',
                      TextStyle(
                          color: cor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5),
                    ))
                .toList(),
          ),
        ),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: 0.25,
            color: CoresRisco.atencao.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
          HorizontalLine(
            y: 0.60,
            color: CoresRisco.critico.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ]),
      ),
    );
  }
}

class _SecaoSmart extends StatelessWidget {
  final Map<String, dynamic> smart;
  const _SecaoSmart({required this.smart});

  @override
  Widget build(BuildContext context) {
    final linhas =
        _rotulosSmart.entries.where((e) => smart.containsKey(e.key)).toList();
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Atributos SMART',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Card(
        margin: const EdgeInsets.only(bottom: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: linhas.map((e) {
              final valor = smart[e.key];
              final numero = valor is num ? valor : 0;
              final alerta = _sintomas.contains(e.key) && numero > 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  SizedBox(
                    width: 165,
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF8A8F98))),
                  ),
                  Text('$valor',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              alerta ? FontWeight.w700 : FontWeight.normal,
                          color: alerta ? CoresRisco.critico : null)),
                  if (alerta) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.warning_amber_rounded,
                        size: 15, color: CoresRisco.critico),
                  ],
                ]),
              );
            }).toList(),
          ),
        ),
      ),
    ]);
  }
}

class _Linha extends StatelessWidget {
  final String rotulo;
  final String valor;
  const _Linha({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 165,
          child: Text(rotulo,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A8F98))),
        ),
        Expanded(
            child: Text(valor.isEmpty ? '--' : valor,
                style: const TextStyle(fontSize: 13.5))),
      ]),
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final Map<String, String> linhas;
  const _Secao({required this.titulo, required this.linhas});

  @override
  Widget build(BuildContext context) {
    if (linhas.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Card(
        margin: const EdgeInsets.only(bottom: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: linhas.entries
                .map((e) => _Linha(rotulo: e.key, valor: e.value))
                .toList(),
          ),
        ),
      ),
    ]);
  }
}
