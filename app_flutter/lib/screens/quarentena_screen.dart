import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import '../utils/formato.dart';
import '../widgets/dialogo_baixa.dart';
import '../widgets/dialogo_localizacao.dart';
import '../widgets/risco_badge.dart';
import 'ficha_screen.dart';

class QuarentenaScreen extends StatelessWidget {
  const QuarentenaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final servico = FirestoreService();

    return StreamBuilder<List<Maquina>>(
      stream: servico.quarentena(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final itens = snap.data!;

        if (itens.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_outlined, size: 50, color: CoresRisco.ok),
                SizedBox(height: 14),
                Text('Nenhuma maquina em quarentena.',
                    style: TextStyle(fontSize: 15)),
                SizedBox(height: 6),
                Text(
                  'Maquinas desconhecidas detectadas na bancada\n'
                  'aparecem aqui para o tecnico cadastrar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98)),
                ),
              ]),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: itens.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${itens.length} '
                  '${itens.length == 1 ? "maquina nao identificada" : "maquinas nao identificadas"} '
                  'aguardando decisao',
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF8A8F98)),
                ),
              );
            }

            final m = itens[i - 1];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FichaScreen(maquina: m)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.help_outline, color: Color(0xFF9B59B6)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(m.serialBios,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        RiscoBadge(maquina: m),
                      ]),
                      const SizedBox(height: 12),
                      Text('${m.fabricante} ${m.modeloPc}'),
                      Text(
                          '${m.cpu} | ${m.ramGb} GB RAM | '
                          '${m.tipoDisco} ${m.capacidadeTexto}',
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF8A8F98))),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.schedule,
                            size: 13, color: Color(0xFF8A8F98)),
                        const SizedBox(width: 5),
                        Text(
                            'Detectada ${formatarRelativo(m.atualizadoEm)}',
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFF8A8F98))),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        FilledButton.icon(
                          onPressed: () => abrirDialogoLocalizacao(
                            context,
                            maquina: m,
                            cadastrando: true,
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Cadastrar'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () => abrirDialogoBaixa(context, m),
                          icon: const Icon(Icons.archive_outlined, size: 18),
                          label: const Text('Dar baixa'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
