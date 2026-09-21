import 'package:flutter/material.dart';

import '../models/maquina.dart';
import '../services/firestore_service.dart';

/// Dialogo de escola e sala, usado em dois lugares:
///  - ficha da maquina, para corrigir ou remanejar
///  - quarentena, para cadastrar uma maquina desconhecida
///
/// Um unico dialogo para os dois casos evita que as telas divirjam com o
/// tempo (validacao diferente, rotulo diferente, comportamento diferente).
class DialogoLocalizacao extends StatefulWidget {
  final Maquina maquina;

  /// true  = maquina em quarentena sendo cadastrada (muda status para ativo)
  /// false = maquina ja ativa sendo remanejada (status nao muda)
  final bool cadastrando;

  /// Escolas ja usadas no parque, oferecidas como sugestao.
  final List<String> escolasConhecidas;

  const DialogoLocalizacao({
    super.key,
    required this.maquina,
    required this.cadastrando,
    this.escolasConhecidas = const [],
  });

  @override
  State<DialogoLocalizacao> createState() => _DialogoLocalizacaoState();
}

class _DialogoLocalizacaoState extends State<DialogoLocalizacao> {
  final _servico = FirestoreService();
  final _chave = GlobalKey<FormState>();
  late final TextEditingController _escola;
  late final TextEditingController _sala;

  bool _salvando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    // Ao cadastrar da quarentena os campos comecam vazios.
    // Ao remanejar, comecam com o valor atual para o usuario so corrigir.
    final e = widget.maquina.escola;
    _escola = TextEditingController(
        text: widget.cadastrando || e == 'Nao atribuida' ? '' : e);
    _sala = TextEditingController(
        text: widget.cadastrando || widget.maquina.sala == '-'
            ? ''
            : widget.maquina.sala);
  }

  @override
  void dispose() {
    _escola.dispose();
    _sala.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_chave.currentState!.validate()) return;

    setState(() {
      _salvando = true;
      _erro = null;
    });

    try {
      final escola = _escola.text.trim();
      final sala = _sala.text.trim();

      if (widget.cadastrando) {
        await _servico.aprovarMaquina(widget.maquina.serialBios, escola, sala);
      } else {
        await _servico.atualizarLocalizacao(
            widget.maquina.serialBios, escola, sala);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = '$e'.contains('permission-denied')
              ? 'Sem permissao para alterar. Saia e entre novamente.'
              : 'Nao foi possivel salvar. Verifique sua conexao.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.cadastrando
          ? 'Cadastrar maquina'
          : 'Alterar localizacao'),
      content: Form(
        key: _chave,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.maquina.serialBios,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: Color(0xFF8A8F98))),
          ),
          const SizedBox(height: 18),

          TextFormField(
            controller: _escola,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Escola',
              prefixIcon: Icon(Icons.school_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Informe a escola' : null,
          ),

          if (widget.escolasConhecidas.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final escola in widget.escolasConhecidas.take(12))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(escola,
                            style: const TextStyle(fontSize: 11.5)),
                        onPressed: () => _escola.text = escola,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          TextFormField(
            controller: _sala,
            textCapitalization: TextCapitalization.words,
            onFieldSubmitted: (_) => _salvar(),
            decoration: const InputDecoration(
              labelText: 'Sala',
              hintText: 'Laboratorio 1, Secretaria...',
              prefixIcon: Icon(Icons.meeting_room_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Informe a sala' : null,
          ),

          if (_erro != null) ...[
            const SizedBox(height: 14),
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
          onPressed: _salvando ? null : _salvar,
          child: _salvando
              ? const SizedBox(
                  height: 17,
                  width: 17,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.cadastrando ? 'Cadastrar' : 'Salvar'),
        ),
      ],
    );
  }
}

/// Abre o dialogo e devolve true se algo foi salvo.
Future<bool> abrirDialogoLocalizacao(
  BuildContext context, {
  required Maquina maquina,
  required bool cadastrando,
  List<String> escolasConhecidas = const [],
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (_) => DialogoLocalizacao(
      maquina: maquina,
      cadastrando: cadastrando,
      escolasConhecidas: escolasConhecidas,
    ),
  );
  return resultado ?? false;
}
