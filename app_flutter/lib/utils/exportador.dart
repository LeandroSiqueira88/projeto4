import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/maquina.dart';
import '../utils/formato.dart';
import '../widgets/risco_badge.dart';

/// Utilitario para exportar o inventario higienizado em formato CSV
/// e acionar o compartilhamento do arquivo gerado.
Future<void> exportarECompartilharCsv(
    BuildContext context, List<Maquina> maquinas) async {
  try {
    if (maquinas.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma máquina encontrada para exportar.')),
        );
      }
      return;
    }

    List<List<dynamic>> rows = [];

    // Cabecalho do relatorio CSV
    rows.add([
      'Número de Série',
      'CIE',
      'Escola',
      'Ambiente / Sala',
      'Fabricante',
      'Modelo',
      'Processador',
      'RAM (GB)',
      'Risco de Falha (%)',
      'Faixa de Risco',
      'Status',
      'Data da Última Visita'
    ]);

    // Linhas de dados
    for (var m in maquinas) {
      rows.add([
        m.numeroSerie,
        m.cie,
        m.escolaNome,
        m.ambiente,
        m.fabricante,
        m.modelo,
        m.processador,
        m.memoriaRamGb,
        m.riscoFalha != null ? (m.riscoFalha! * 100).toStringAsFixed(1) : '0',
        CoresRisco.rotulo(m.faixa),
        m.statusEquipamento,
        m.dataVisita != null ? formatarData(m.dataVisita) : 'N/A',
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);

    final output = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${output.path}/inventario_ure_$timestamp.csv');
    await file.writeAsString(csvData, encoding: utf8);

    if (context.mounted) {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Relatório de Inventário Preditivo - URE (${maquinas.length} registros)',
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar relatório: $e')),
      );
    }
  }
}
