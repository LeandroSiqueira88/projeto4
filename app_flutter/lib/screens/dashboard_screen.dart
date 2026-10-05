import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import '../widgets/risco_badge.dart';
import 'ficha_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int aba, {String? filtro})? onNavegar;
  const DashboardScreen({super.key, this.onNavegar});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _servico = FirestoreService();
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
  Widget build(BuildContext context) {
    return StreamBuilder<List<Maquina>>(
      stream: _maquinasStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Erro(
            mensagem: '${snap.error}',
            onTentarNovamente: _recarregar,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final todas = snap.data!;
        final maquinas = todas.where((m) => m.ativa).toList();
        final baixadas = todas.where((m) => m.baixada).length;
        if (todas.isEmpty) return const _Vazio();

        final criticas =
            maquinas.where((m) => m.faixa == FaixaRisco.critico).toList()
              ..sort((a, b) => (b.riscoFalha ?? 0).compareTo(a.riscoFalha ?? 0));
        final atencao =
            maquinas.where((m) => m.faixa == FaixaRisco.atencao).length;
        final semDados =
            maquinas.where((m) => m.faixa == FaixaRisco.semDados).length;
        final ok = maquinas.where((m) => m.faixa == FaixaRisco.ok).length;
        final quarentena = todas.where((m) => m.emQuarentena).length;

        return LayoutBuilder(builder: (context, restricoes) {
          final largura = restricoes.maxWidth;
          final colunas = largura > 1100 ? 4 : largura > 760 ? 3 : 2;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Visão geral do parque',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
              if (baixadas > 0) ...[
                const SizedBox(height: 3),
                Text(
                    '$baixadas ${baixadas == 1 ? "máquina baixada" : "máquinas baixadas"} não contabilizadas',
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
                  mainAxisExtent: 108, // Aumentado para acomodar variações de fonte
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (context, i) => [
                  CartaoMetrica(
                      titulo: 'Máquinas',
                      valor: '${maquinas.length}',
                      icone: Icons.desktop_windows_outlined,
                      cor: const Color(0xFF4A7DD6),
                      onTap: () => widget.onNavegar?.call(1, filtro: 'todas')),
                  CartaoMetrica(
                      titulo: 'Risco crítico',
                      valor: '${criticas.length}',
                      icone: Icons.error_outline,
                      cor: CoresRisco.critico,
                      onTap: () => widget.onNavegar?.call(1, filtro: 'critico')),
                  CartaoMetrica(
                      titulo: 'Em atenção',
                      valor: '$atencao',
                      icone: Icons.warning_amber_outlined,
                      cor: CoresRisco.atencao,
                      onTap: () => widget.onNavegar?.call(1, filtro: 'atencao')),
                  CartaoMetrica(
                      titulo: 'Quarentena',
                      valor: '$quarentena',
                      icone: Icons.help_outline,
                      cor: const Color(0xFF9B59B6),
                      onTap: () => widget.onNavegar?.call(2)),
                ][i],
              ),

              const SizedBox(height: 30),
              const Text('Distribuição de risco',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              BarraProporcao(itens: [
                (rotulo: 'OK', valor: ok, cor: CoresRisco.ok),
                (rotulo: 'Atenção', valor: atencao, cor: CoresRisco.atencao),
                (rotulo: 'Crítico', valor: criticas.length, cor: CoresRisco.critico),
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
                    Text('Nenhuma máquina em risco crítico.'),
                  ]),
                )
              else
                ...criticas.take(8).map((m) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(m.numeroSerie,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${m.escolaTexto} - ${m.ambienteTexto}\n'
                            '${m.fabricante} ${m.modelo}'),
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
                      'e mais ${criticas.length - 8} em risco crítico. '
                      'Veja a lista completa em Inventário.',
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

class CartaoMetrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;
  final VoidCallback? onTap;

  const CartaoMetrica({
    super.key,
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cor.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icone, color: cor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        valor,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: cor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cor.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BarraProporcao extends StatelessWidget {
  final List<({String rotulo, int valor, Color cor})> itens;

  const BarraProporcao({super.key, required this.itens});

  @override
  Widget build(BuildContext context) {
    final total = itens.fold(0, (sum, item) => sum + item.valor);
    if (total == 0) return const SizedBox();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: Row(
              children: itens.map((item) {
                final perc = item.valor / total;
                if (perc == 0) return const SizedBox();
                return Flexible(
                  flex: (perc * 1000).toInt(),
                  child: Container(color: item.cor),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: itens.map((item) {
            final perc = (item.valor / total * 100).toStringAsFixed(0);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: item.cor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item.rotulo}: ${item.valor} ($perc%)',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            );
          }).toList(),
        ),
      ],
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
          Text('Nenhuma máquina no inventário ainda.',
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
  final VoidCallback onTentarNovamente;
  const _Erro({required this.mensagem, required this.onTentarNovamente});

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
                  ? 'Sem permissão para ler o banco.'
                  : 'Erro ao carregar os dados.',
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(
              semPermissao
                  ? 'As regras do Firestore exigem usuário autenticado.\n'
                      'Saia e entre novamente.'
                  : mensagem,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF8A8F98))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onTentarNovamente,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tentar Novamente'),
          ),
        ]),
      ),
    );
  }
}
