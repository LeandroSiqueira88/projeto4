import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';
import 'risco_badge.dart';

/// Dialogo de BAIXA DE PATRIMONIO (exclusao logica).
///
/// A maquina sai do inventario ativo mas o registro e o historico ficam no
/// banco. Motivo e obrigatorio - baixa sem justificativa nao serve para
/// prestacao de contas.
class DialogoBaixa extends StatefulWidget {
  final Maquina maquina;
  const DialogoBaixa({super.key, required this.maquina});

  @override
  State<DialogoBaixa> createState() => _DialogoBaixaState();
}

class _DialogoBaixaState extends State<DialogoBaixa> {
  final _servico = FirestoreService();
  final _observacao = TextEditingController();
  String? _motivo;
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_motivo == null) {
      setState(() => _erro = 'Selecione o motivo da baixa.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      await _servico.darBaixa(widget.maquina.serialBios, _motivo!,
          observacao: _observacao.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = '$e'.contains('permission-denied')
              ? 'Sem permissao. Publique as regras atualizadas do Firestore.'
              : 'Nao foi possivel salvar. Verifique sua conexao.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dar baixa no patrimonio'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.maquina.serialBios,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: Color(0xFF8A8F98))),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            initialValue: _motivo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Motivo da baixa',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final m in MotivosBaixa.lista)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: _salvando
                ? null
                : (v) => setState(() {
                      _motivo = v;
                      _erro = null;
                    }),
          ),

          const SizedBox(height: 14),
          TextField(
            controller: _observacao,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observacao (opcional)',
              hintText: 'Numero do processo, laudo tecnico...',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: CoresRisco.ok.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.history, size: 17, color: CoresRisco.ok),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'O historico de leituras sera preservado. '
                  'A baixa pode ser revertida depois.',
                  style: TextStyle(fontSize: 11.5, color: CoresRisco.ok),
                ),
              ),
            ]),
          ),

          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _confirmar,
          child: _salvando
              ? const SizedBox(
                  height: 17,
                  width: 17,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Dar baixa'),
        ),
      ],
    );
  }
}

/// Dialogo de EXCLUSAO DEFINITIVA.
///
/// Apaga o registro e todo o historico. Exige digitar o serial para
/// confirmar - a friccao e proposital, porque a operacao nao tem volta.
class DialogoExclusao extends StatefulWidget {
  final Maquina maquina;
  const DialogoExclusao({super.key, required this.maquina});

  @override
  State<DialogoExclusao> createState() => _DialogoExclusaoState();
}

class _DialogoExclusaoState extends State<DialogoExclusao> {
  final _servico = FirestoreService();
  final _confirmacao = TextEditingController();
  final _motivo = TextEditingController();
  bool _excluindo = false;
  String? _erro;

  @override
  void dispose() {
    _confirmacao.dispose();
    _motivo.dispose();
    super.dispose();
  }

  bool get _podeExcluir =>
      _confirmacao.text.trim().toUpperCase() ==
          widget.maquina.serialBios.toUpperCase() &&
      _motivo.text.trim().isNotEmpty;

  Future<void> _excluir() async {
    setState(() {
      _excluindo = true;
      _erro = null;
    });

    try {
      await _servico.excluirDefinitivo(
          widget.maquina.serialBios, _motivo.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _excluindo = false;
          _erro = '$e'.contains('permission-denied')
              ? 'Sem permissao. Publique as regras atualizadas do Firestore.'
              : 'Nao foi possivel excluir. Verifique sua conexao.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final erroCor = Theme.of(context).colorScheme.error;

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.warning_amber_rounded, color: erroCor),
        const SizedBox(width: 10),
        const Text('Excluir definitivamente'),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: erroCor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Esta acao apaga o registro e todo o historico de leituras. '
              'Nao tem volta.\n\n'
              'Para equipamento que saiu de uso, prefira DAR BAIXA - '
              'preserva o historico e pode ser revertida.',
              style: TextStyle(fontSize: 12, color: erroCor),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _motivo,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Motivo da exclusao',
              hintText: 'Registro duplicado, cadastro por engano...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),

          Align(
            alignment: Alignment.centerLeft,
            child: Text('Digite o serial para confirmar:',
                style: const TextStyle(
                    fontSize: 12.5, color: Color(0xFF8A8F98))),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(widget.maquina.serialBios,
                style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmacao,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(_erro!, style: TextStyle(fontSize: 12.5, color: erroCor)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _excluindo ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_podeExcluir && !_excluindo) ? _excluir : null,
          style: FilledButton.styleFrom(backgroundColor: erroCor),
          child: _excluindo
              ? const SizedBox(
                  height: 17,
                  width: 17,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Excluir'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Atalhos
// ---------------------------------------------------------------------------

Future<bool> abrirDialogoBaixa(BuildContext context, Maquina maquina) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => DialogoBaixa(maquina: maquina),
  );
  return r ?? false;
}

Future<bool> abrirDialogoExclusao(
    BuildContext context, Maquina maquina) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogoExclusao(maquina: maquina),
  );
  return r ?? false;
}
