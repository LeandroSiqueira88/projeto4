/// Formatacao de datas para exibicao.
///
/// Evita mostrar "2026-09-20T10:37:14.123456+00:00" na tela. O tecnico
/// precisa saber ha quanto tempo a maquina foi vista, nao o timestamp exato.

String formatarData(DateTime? data) {
  if (data == null) return '--';
  final d = data.toLocal();
  final dois = (int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
}

/// Texto relativo: "ha 3 dias", "ontem", "agora".
/// Na lista do inventario isso comunica melhor que a data cheia -
/// o que importa e se a leitura e recente ou antiga.
String formatarRelativo(DateTime? data) {
  if (data == null) return 'nunca lida';

  final agora = DateTime.now();
  final d = data.toLocal();
  final diferenca = agora.difference(d);

  if (diferenca.isNegative) return formatarData(data);
  if (diferenca.inMinutes < 2) return 'agora';
  if (diferenca.inMinutes < 60) return 'ha ${diferenca.inMinutes} min';
  if (diferenca.inHours < 24) return 'ha ${diferenca.inHours} h';
  if (diferenca.inDays == 1) return 'ontem';
  if (diferenca.inDays < 30) return 'ha ${diferenca.inDays} dias';
  if (diferenca.inDays < 365) {
    final meses = (diferenca.inDays / 30).floor();
    return meses == 1 ? 'ha 1 mes' : 'ha $meses meses';
  }
  final anos = (diferenca.inDays / 365).floor();
  return anos == 1 ? 'ha 1 ano' : 'ha $anos anos';
}

/// Leitura antiga indica que a maquina nao passa pela bancada ha muito tempo.
/// O historico dela esta desatualizado e a predicao perde qualidade.
bool leituraAntiga(DateTime? data, {int diasLimite = 180}) {
  if (data == null) return true;
  return DateTime.now().difference(data.toLocal()).inDays > diasLimite;
}
