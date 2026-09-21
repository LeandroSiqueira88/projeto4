import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import '../utils/formato.dart';
import '../widgets/risco_badge.dart';
import 'ficha_screen.dart';

class ListaScreen extends StatefulWidget {
  const ListaScreen({super.key});

  @override
  State<ListaScreen> createState() => _ListaScreenState();
}

class _ListaScreenState extends State<ListaScreen> {
  final _servico = FirestoreService();
  final _busca = TextEditingController();
  String _filtro = 'todas';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  bool _passa(Maquina m) {
    final termo = _busca.text.trim().toLowerCase();
    if (termo.isNotEmpty) {
      final alvo = '${m.serialBios} ${m.escola} ${m.sala} ${m.modeloPc} '
              '${m.modeloDisco} ${m.cpu}'
          .toLowerCase();
      if (!alvo.contains(termo)) return false;
    }
    return switch (_filtro) {
      'critico' => m.ativa && m.faixa == FaixaRisco.critico,
      'atencao' => m.ativa && m.faixa == FaixaRisco.atencao,
      'quarentena' => m.emQuarentena,
      'antigas' => !m.baixada && leituraAntiga(m.atualizadoEm),
      'baixadas' => m.baixada,
      // "Todas" mostra o inventario vigente: maquinas baixadas ficam fora,
      // acessiveis pelo filtro proprio. Inventario ativo nao deve contar
      // equipamento que ja saiu do patrimonio.
      _ => !m.baixada,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar por serial, escola, sala ou modelo',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 19),
                    onPressed: () {
                      _busca.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (final f in const [
            ('todas', 'Todas'),
            ('critico', 'Critico'),
            ('atencao', 'Atencao'),
            ('quarentena', 'Quarentena'),
            ('antigas', 'Leitura antiga'),
            ('baixadas', 'Baixadas'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: _filtro == f.$1,
                onSelected: (_) => setState(() => _filtro = f.$1),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: StreamBuilder<List<Maquina>>(
          stream: _servico.maquinas(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erro ao carregar: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF8A8F98))),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final itens = snap.data!.where(_passa).toList();
            if (itens.isEmpty) {
              return const Center(child: Text('Nenhum resultado.'));
            }

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${itens.length} '
                      '${itens.length == 1 ? "maquina" : "maquinas"}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A8F98))),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: itens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ItemMaquina(maquina: itens[i]),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _ItemMaquina extends StatelessWidget {
  final Maquina maquina;
  const _ItemMaquina({required this.maquina});

  @override
  Widget build(BuildContext context) {
    final antiga = !maquina.baixada && leituraAntiga(maquina.atualizadoEm);

    return Card(
      child: ListTile(
        leading: Icon(
          maquina.baixada
              ? Icons.archive_outlined
              : maquina.emQuarentena
                  ? Icons.help_outline
                  : Icons.desktop_windows_outlined,
          color: maquina.baixada ? const Color(0xFF8A8F98) : null,
        ),
        title: Row(children: [
          Flexible(
            child: Text(maquina.serialBios,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: maquina.baixada
                        ? TextDecoration.lineThrough
                        : null,
                    color: maquina.baixada ? const Color(0xFF8A8F98) : null)),
          ),
          if (maquina.baixada) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8A8F98).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text('BAIXADA',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A8F98))),
            ),
          ],
        ]),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text('${maquina.escolaTexto} - ${maquina.salaTexto}'),
            Text(
                '${maquina.cpu} | ${maquina.ramGb} GB RAM | '
                '${maquina.tipoDisco} ${maquina.capacidadeTexto}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            // Data da ultima leitura. Em formato relativo porque o que
            // importa e se a leitura e recente, nao o timestamp exato.
            Row(children: [
              Icon(Icons.schedule,
                  size: 13,
                  color:
                      antiga ? CoresRisco.atencao : const Color(0xFF8A8F98)),
              const SizedBox(width: 5),
              Text(
                maquina.baixada
                    ? 'Baixada ${formatarRelativo(maquina.dataBaixa)}'
                    : 'Lida ${formatarRelativo(maquina.atualizadoEm)}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: antiga ? FontWeight.w600 : FontWeight.normal,
                    color: antiga
                        ? CoresRisco.atencao
                        : const Color(0xFF8A8F98)),
              ),
            ]),
          ],
        ),
        isThreeLine: true,
        trailing: RiscoBadge(maquina: maquina),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FichaScreen(maquina: maquina)),
        ),
      ),
    );
  }
}
