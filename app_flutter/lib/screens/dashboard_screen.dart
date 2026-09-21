import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import '../widgets/risco_badge.dart';
import 'ficha_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final servico = FirestoreService();

    return StreamBuilder<List<Maquina>>(
      stream: servico.maquinas(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _Erro(mensagem: '${snap.error}');
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // Maquinas baixadas ficam fora dos indicadores: o painel mostra o
        // parque vigente, nao o historico de patrimonio. Elas continuam
        // acessiveis pelo filtro "Baixadas" no inventario.
        final todas = snap.data!;
        final maquinas = todas.where((m) => !m.baixada).toList();
        final baixadas = todas.length - maquinas.length;
        if (todas.isEmpty) return const _Vazio();

        final criticas =
            maquinas.where((m) => m.faixa == FaixaRisco.critico).toList()
              ..sort((a, b) => (b.riscoFalha ?? 0).compareTo(a.riscoFalha ?? 0));
        final atencao =
            maquinas.where((m) => m.faixa == FaixaRisco.atencao).length;
        final semDados =
            maquinas.where((m) => m.faixa == FaixaRisco.semDados).length;
        final ok = maquinas.where((m) => m.faixa == FaixaRisco.ok).length;
        final quarentena = maquinas.where((m) => m.emQuarentena).length;

        return LayoutBuilder(builder: (context, restricoes) {
          // Numero de colunas conforme a largura. A altura de cada cartao
          // e fixa (mainAxisExtent), entao eles nao esticam em tela larga.
          final largura = restricoes.maxWidth;
          final colunas = largura > 1100
              ? 4
              : largura > 760
                  ? 3
                  : 2;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Visao geral do parque',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              if (baixadas > 0) ...[
                const SizedBox(height: 3),
                Text(
                    '$baixadas ${baixadas == 1 ? "maquina baixada nao contabilizada" : "maquinas baixadas nao contabilizadas"}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8A8F98))),
              ],
              const SizedBox(height: 16),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colunas,
                  mainAxisExtent: 74, // altura fixa do cartao
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (context, i) => [
                  CartaoMetrica(
                      titulo: 'Maquinas',
                      valor: '${maquinas.length}',
                      icone: Icons.desktop_windows_outlined,
                      cor: const Color(0xFF4A7DD6)),
                  CartaoMetrica(
                      titulo: 'Risco critico',
                      valor: '${criticas.length}',
                      icone: Icons.error_outline,
                      cor: CoresRisco.critico),
                  CartaoMetrica(
                      titulo: 'Em atencao',
                      valor: '$atencao',
                      icone: Icons.warning_amber_outlined,
                      cor: CoresRisco.atencao),
                  CartaoMetrica(
                      titulo: 'Quarentena',
                      valor: '$quarentena',
                      icone: Icons.help_outline,
                      cor: const Color(0xFF9B59B6)),
                ][i],
              ),

              const SizedBox(height: 30),
              const Text('Distribuicao de risco',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              BarraProporcao(itens: [
                (rotulo: 'OK', valor: ok, cor: CoresRisco.ok),
                (rotulo: 'Atencao', valor: atencao, cor: CoresRisco.atencao),
                (rotulo: 'Critico', valor: criticas.length, cor: CoresRisco.critico),
                (rotulo: 'Sem dados', valor: semDados, cor: CoresRisco.semDados),
              ]),

              const SizedBox(height: 32),
              const Text('Trocar com prioridade',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Discos com maior probabilidade de falha em 30 dias',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
              const SizedBox(height: 12),

              if (criticas.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 20, color: CoresRisco.ok),
                    SizedBox(width: 10),
                    Text('Nenhuma maquina em risco critico.'),
                  ]),
                )
              else
                ...criticas.take(8).map((m) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(m.serialBios,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${m.escolaTexto} - ${m.salaTexto}\n'
                            '${m.modeloDisco} ${m.capacidadeTexto}'),
                        isThreeLine: true,
                        trailing: RiscoBadge(maquina: m),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => FichaScreen(maquina: m)),
                        ),
                      ),
                    )),

              if (criticas.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'e mais ${criticas.length - 8} em risco critico. '
                      'Veja a lista completa em Inventario.',
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFF8A8F98))),
                ),
            ],
          );
        });
      },
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 52, color: Color(0xFF8A8F98)),
          SizedBox(height: 14),
          Text('Nenhuma maquina no inventario ainda.',
              style: TextStyle(fontSize: 16)),
          SizedBox(height: 6),
          Text('Rode a bancada: python bancada/main.py',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
        ]),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  final String mensagem;
  const _Erro({required this.mensagem});

  @override
  Widget build(BuildContext context) {
    final semPermissao = mensagem.contains('permission-denied') ||
        mensagem.toLowerCase().contains('insufficient');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 48, color: CoresRisco.critico),
          const SizedBox(height: 14),
          Text(
              semPermissao
                  ? 'Sem permissao para ler o banco.'
                  : 'Erro ao carregar os dados.',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
              semPermissao
                  ? 'As regras do Firestore exigem usuario autenticado.\n'
                      'Saia e entre novamente.'
                  : mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
        ]),
      ),
    );
  }
}
