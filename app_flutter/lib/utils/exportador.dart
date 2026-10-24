import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/maquina.dart';
import '../utils/formato.dart';
import '../widgets/risco_badge.dart';

/// Exporta diretamente para CSV (compativel com Excel em PT-BR usando ponto e vírgula e BOM UTF-8).
Future<void> exportarCsvDireto(BuildContext context, List<Maquina> maquinas) async {
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

    // Cabecalho com acentuacao correta
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

    // Dados
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

    // Uso de ponto e virgula (;) como delimitador para tabular corretamente no Excel (PT-BR)
    String csvData = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    
    // Adiciona o BOM UTF-8 (\uFEFF) para que o Excel detecte UTF-8 automaticamente e exiba acentos (Última, Série)
    final bytes = utf8.encode('\uFEFF$csvData');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'inventario_ure_$timestamp.csv';

    XFile xFile;
    if (kIsWeb) {
      xFile = XFile.fromData(bytes, mimeType: 'text/csv', name: fileName);
    } else {
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(bytes);
      xFile = XFile(file.path);
    }

    if (context.mounted) {
      await Share.shareXFiles(
        [xFile],
        text: 'Relatório CSV - Inventário URE (${maquinas.length} registros)',
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar CSV: $e')),
      );
    }
  }
}

/// Exporta diretamente para PDF (Relatório Institucional URE / UNIVESP).
Future<void> exportarPdfDireto(BuildContext context, List<Maquina> maquinas) async {
  try {
    if (maquinas.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma máquina encontrada para exportar.')),
        );
      }
      return;
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context contextPdf) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('UNIVESP — PJI410 · Projeto Integrador IV',
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text('Relatório de Inventário Preditivo - URE',
                          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Text('Gerado em: ${DateTime.now().toString().substring(0, 16)}',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Total de equipamentos listados: ${maquinas.length}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              context: contextPdf,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              cellStyle: pw.TextStyle(fontSize: 8),
              headers: [
                'Número de Série',
                'CIE',
                'Escola',
                'Ambiente',
                'Fabricante',
                'Modelo',
                'RAM',
                'Risco (%)',
                'Faixa',
                'Status'
              ],
              data: maquinas.map((m) => [
                m.numeroSerie,
                m.cie,
                m.escolaNome,
                m.ambiente,
                m.fabricante,
                m.modelo,
                '${m.memoriaRamGb} GB',
                m.riscoFalha != null ? '${(m.riscoFalha! * 100).toStringAsFixed(1)}%' : '0%',
                CoresRisco.rotulo(m.faixa),
                m.statusEquipamento,
              ]).toList(),
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'relatorio_inventario_$timestamp.pdf';

    XFile xFile;
    if (kIsWeb) {
      xFile = XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName);
    } else {
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(bytes);
      xFile = XFile(file.path);
    }

    if (context.mounted) {
      await Share.shareXFiles(
        [xFile],
        text: 'Relatório PDF - Inventário URE (${maquinas.length} registros)',
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar PDF: $e')),
      );
    }
  }
}
