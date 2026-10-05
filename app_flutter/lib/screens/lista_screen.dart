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
  late Stream<List<Maquina>> _maquinasStream;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  void _recarregar() {
    setState(() {
      _maquinasStream = _servico.maquinas();
    });
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  bool _passa(Maquina m) {
    final termo = _busca.text.trim().toLowerCase();
    if (termo.isNotEmpty) {
      final alvo = '${m.numeroSerie} ${m.escolaNome} ${m.ambiente} ${m.modelo} '
          '${m.processador} ${m.hostname}'
          .toLowerCase();
      if (!alvo.contains(termo)) return false;
    }
    return switch (_filtro) {
      'critico' => m.ativa && m.faixa == FaixaRisco.critico,
      'atencao' => m.ativa && m.faixa == FaixaRisco.atencao,
      'quarentena' => m.emQuarentena,
      'antigas' => !m.baixada && leituraAntiga(m.dataVisita),
      'baixadas' => m.baixada,
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
            hintText: 'Buscar por serial, escola, ambiente ou modelo',
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
            ('critico', 'Crítico'),
            ('atencao', 'Atenção'),
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
          stream: _maquinasStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 42, color: CoresRisco.critico),
                      const SizedBox(height: 12),
                      Text('Erro ao carregar: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF8A8F98))),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _recarregar,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Tentar Novamente'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final totalGeral = snap.data!.length;
            final itens = snap.data!.where(_passa).toList();

            if (itens.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off, size: 48, color: Color(0xFF8A8F98)),
                      const SizedBox(height: 12),
                      Text(
                        totalGeral == 0
                            ? 'Nenhuma máquina cadastrada no inventário.'
                            : 'Nenhum resultado para os filtros/busca aplicados.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (totalGeral > 0) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _busca.clear();
                              _filtro = 'todas';
                            });
                          },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Limpar busca e filtros'),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${itens.length} '
                          '${itens.length == 1 ? "máquina" : "máquinas"}',
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
    final antiga = !maquina.baixada && leituraAntiga(maquina.dataVisita);

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
            child: Text(maquina.numeroSerie,
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
            Text(
              '${maquina.escolaTexto} - ${maquina.ambienteTexto}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
                '${maquina.processador} | ${maquina.memoriaRamGb} GB RAM',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.schedule,
                  size: 13,
                  color:
                  antiga ? CoresRisco.atencao : const Color(0xFF8A8F98)),
              const SizedBox(width: 5),
              Text(
                maquina.baixada
                    ? 'Baixada ${formatarRelativo(maquina.dataVisita)}'
                    : 'Lida ${formatarRelativo(maquina.dataVisita)}',
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
