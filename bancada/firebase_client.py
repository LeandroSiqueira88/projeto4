"""
firebase_client.py
==================
Envia o inventario coletado na bancada para o Cloud Firestore.

COMO OBTER A CREDENCIAL (faca uma vez):
  1. console.firebase.google.com -> criar projeto
  2. Configuracoes do projeto -> Contas de servico
  3. "Gerar nova chave privada" -> baixa um .json
  4. Salve como bancada/serviceAccountKey.json
  5. NUNCA commite nem compartilhe esse arquivo. Ja esta no .gitignore.

ESTRUTURA NO FIRESTORE:
  maquinas/{serial_bios}
      dados atuais da maquina (sobrescrito a cada leitura)
      + subcolecao leituras/{timestamp} = historico completo
  eventos/{auto}
      log de quarentena, risco critico, peca trocada
  bancadas/{id_bancada}
      ultimo ping, nome, URE

Modo offline: se nao der para conectar, o cliente grava em
bancada/fila_offline.jsonl e sincroniza na proxima execucao com internet.
Bancada em escola publica cai da rede o tempo todo - isso nao e luxo.
"""

import json
import os
from datetime import datetime, timezone

DIR = os.path.dirname(os.path.abspath(__file__))
CRED = os.path.join(DIR, "serviceAccountKey.json")
FILA = os.path.join(DIR, "fila_offline.jsonl")

_db = None

# Guarda o motivo exato da ultima falha, para o diagnostico nao mentir.
# (Antes, biblioteca faltando aparecia como "sem credencial" e mandava o
#  usuario procurar problema no arquivo errado.)
_ultimo_erro = ""


def _agora():
    return datetime.now().astimezone().isoformat()


def motivo_desconexao():
    """Explica, em portugues claro, por que nao deu para conectar."""
    if not _ultimo_erro:
        return ""
    if "firebase_admin" in _ultimo_erro:
        return ("Biblioteca firebase-admin nao instalada.\n"
                "  Resolva com: pip install firebase-admin\n"
                "  (com o ambiente virtual .venv ATIVO)")
    if _ultimo_erro == "credencial ausente":
        return (f"Credencial nao encontrada em:\n  {CRED}\n"
                "  Gere em: Firebase > Configuracoes do projeto > Contas de servico\n"
                "  e salve com esse nome exato.")
    return _ultimo_erro


def conectar():
    """Devolve o client do Firestore, ou None se nao der para conectar."""
    global _db, _ultimo_erro
    if _db is not None:
        return _db

    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError as e:
        _ultimo_erro = f"firebase_admin ausente: {e}"
        return None

    if not os.path.exists(CRED):
        _ultimo_erro = "credencial ausente"
        return None

    try:
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(CRED))
        _db = firestore.client()
        _ultimo_erro = ""
        return _db
    except Exception as e:
        _ultimo_erro = str(e)
        return None


def _enfileirar(tipo, payload):
    with open(FILA, "a", encoding="utf-8") as f:
        f.write(json.dumps({"tipo": tipo, "payload": payload,
                            "enfileirado_em": _agora()},
                           ensure_ascii=False) + "\n")


def salvar_maquina(registro):
    """
    registro precisa ter 'serial_bios'.
    Grava/atualiza o documento e acrescenta uma entrada no historico.
    """
    serial = registro.get("serial_bios")
    if not serial:
        raise ValueError("registro sem serial_bios")

    registro = dict(registro)
    registro["atualizado_em"] = _agora()

    db = conectar()
    if db is None:
        _enfileirar("maquina", registro)
        return {"enviado": False, "motivo": _ultimo_erro or "offline"}

    doc = db.collection("maquinas").document(serial)
    doc.set(registro, merge=True)
    doc.collection("leituras").document(
        registro["atualizado_em"].replace(":", "-")
    ).set(registro)
    return {"enviado": True, "doc": f"maquinas/{serial}"}


def registrar_evento(tipo, serial, descricao, extra=None):
    ev = {"tipo": tipo, "serial_bios": serial, "descricao": descricao,
          "criado_em": _agora()}
    if extra:
        ev.update(extra)

    db = conectar()
    if db is None:
        _enfileirar("evento", ev)
        return {"enviado": False}
    db.collection("eventos").add(ev)
    return {"enviado": True}


def ping_bancada(id_bancada, ure=None):
    db = conectar()
    if db is None:
        return {"enviado": False}
    db.collection("bancadas").document(id_bancada).set(
        {"id": id_bancada, "ure": ure, "ultimo_ping": _agora()}, merge=True)
    return {"enviado": True}


def buscar_maquina(serial_bios):
    """Devolve o documento da maquina, ou None se nunca foi cadastrada."""
    db = conectar()
    if db is None:
        return None
    snap = db.collection("maquinas").document(serial_bios).get()
    return snap.to_dict() if snap.exists else None


def ultima_leitura(serial_bios):
    """
    Leitura anterior da maquina, usada para calcular as features d7_*, que
    medem a VELOCIDADE de degradacao dos contadores SMART. Sao as features de
    maior peso no modelo (d7_smart_187_raw e a 2a mais importante), entao sem
    elas a predicao fica bem pior.

    ATENCAO A ORDEM: main.py chama esta funcao ANTES de gravar a leitura atual.
    Logo o documento mais recente do historico (docs[0]) JA E a leitura
    anterior. Pegar docs[1] aqui pularia uma leitura e, com apenas um registro
    no historico, devolveria None - fazendo o sistema achar que toda maquina
    estava passando pela bancada pela primeira vez.
    """
    db = conectar()
    if db is None:
        return None
    q = (db.collection("maquinas").document(serial_bios)
           .collection("leituras")
           .order_by("atualizado_em", direction="DESCENDING")
           .limit(1).stream())
    docs = [d.to_dict() for d in q]
    return docs[0] if docs else None


def sincronizar_fila():
    """Envia tudo que ficou pendente enquanto a bancada estava offline."""
    if not os.path.exists(FILA):
        return {"pendentes": 0, "enviados": 0}
    db = conectar()
    if db is None:
        with open(FILA, encoding="utf-8") as f:
            return {"pendentes": sum(1 for _ in f), "enviados": 0}

    with open(FILA, encoding="utf-8") as f:
        itens = [json.loads(l) for l in f if l.strip()]

    enviados, restantes = 0, []
    for it in itens:
        try:
            if it["tipo"] == "maquina":
                salvar_maquina(it["payload"])
            else:
                p = it["payload"]
                registrar_evento(p["tipo"], p["serial_bios"], p["descricao"])
            enviados += 1
        except Exception:
            restantes.append(it)

    if restantes:
        with open(FILA, "w", encoding="utf-8") as f:
            for it in restantes:
                f.write(json.dumps(it, ensure_ascii=False) + "\n")
    else:
        os.remove(FILA)

    return {"pendentes": len(restantes), "enviados": enviados}


if __name__ == "__main__":
    db = conectar()
    if db:
        print("[ok] Firestore conectado.")
        res = sincronizar_fila()
        if res["enviados"]:
            print(f"[ok] {res['enviados']} registro(s) da fila offline "
                  f"sincronizado(s).")
        if res["pendentes"]:
            print(f"[!] {res['pendentes']} ainda pendente(s).")
        if not res["enviados"] and not res["pendentes"]:
            print("[ok] Nada pendente na fila offline.")
    else:
        print("[!] Nao foi possivel conectar ao Firestore.\n")
        print(motivo_desconexao())
        print("\nModo offline ativo: os envios ficam guardados em")
        print(f"  {FILA}")
        print("e sobem sozinhos assim que a conexao funcionar.")