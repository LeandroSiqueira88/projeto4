"""
main.py
=======
Orquestrador da bancada. E o programa que o tecnico roda.

FLUXO COMPLETO:
  1. Conecta no Arduino (valida que a bancada fisica esta plugada)
  2. Le hardware da maquina (BIOS, CPU, RAM, disco + SMART)
  3. Busca a leitura anterior dessa maquina no Firestore (para as features d7_*)
  4. Calcula o risco de falha do disco com o modelo treinado
  5. Manda o Arduino acender o LED correspondente
  6. Envia o inventario para o Firestore
  7. Sincroniza qualquer pendencia offline

USO:
  python main.py                 # ciclo unico
  python main.py --loop          # fica esperando; ENTER dispara nova leitura
  python main.py --simular       # sem Arduino e sem Firebase (para desenvolver)
  python main.py --porta COM3    # forca a porta serial

PRECISA DE ADMINISTRADOR (Windows) ou sudo (Linux) para ler BIOS e SMART.
"""

import argparse
import json
import os
import sys
import uuid
from datetime import datetime, timezone

import arduino
import firebase_client as fb
import leitor_hardware as hw
import prever_risco

DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(DIR, "config.json")

C_VERDE = "\033[92m"
C_AMAR = "\033[93m"
C_VERM = "\033[91m"
C_CINZA = "\033[90m"
C_OFF = "\033[0m"

COR_FAIXA = {"OK": C_VERDE, "ATENCAO": C_AMAR, "CRITICO": C_VERM,
             "QUARENTENA": C_VERM}


def carregar_config():
    padrao = {"id_bancada": "URE-01-BANCADA-01", "ure": "URE Exemplo",
              "porta_serial": None, "operador": "tecnico"}
    if os.path.exists(CONFIG):
        with open(CONFIG, encoding="utf-8") as f:
            padrao.update(json.load(f))
    return padrao


def cabecalho(cfg):
    print("=" * 66)
    print("  BANCADA DE VALIDACAO FISICA E INVENTARIO PREDITIVO")
    print(f"  {cfg['id_bancada']}  |  {cfg['ure']}")
    print("=" * 66)


ARQUIVO_ESCOLAS = os.path.join(DIR, "escolas.json")


def carregar_escolas():
    if os.path.exists(ARQUIVO_ESCOLAS):
        try:
            with open(ARQUIVO_ESCOLAS, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return [
        {"cie": "999001", "escola": "EE Prof. Joao", "endereco": "Rua das Flores, 123", "sala": "Lab 01"},
        {"cie": "999002", "escola": "EE Maria da Silva", "endereco": "Av. Brasil, 500", "sala": "Sala de Informatica"},
    ]


def obter_vinculo_escola(serial, simular=False):
    print("\n[2/5] Consultando cadastro e vinculo escolar...")
    conhecida = None if simular else fb.buscar_maquina(serial)

    if conhecida and conhecida.get("cie"):
        cie = conhecida.get("cie", "")
        escola = conhecida.get("escola") or conhecida.get("escola_nome", "")
        sala = conhecida.get("sala") or conhecida.get("ambiente", "")
        print(f"{C_VERDE}      Maquina ja cadastrada:{C_OFF}")
        print(f"      CIE    : {cie}")
        print(f"      Escola : {escola}")
        print(f"      Sala   : {sala}")
        resp = input(f"      Deseja manter este vinculo? [S/n]: ").strip().lower()
        if resp in ("", "s", "sim"):
            return cie, escola, sala, "ativo"

    escolas = carregar_escolas()
    cie_input = input("\n      >>> Digite o CIE da escola: ").strip()

    encontrada = next((e for e in escolas if e["cie"] == cie_input), None)
    if encontrada:
        cie = encontrada["cie"]
        escola = encontrada["escola"]
        sala_padrao = encontrada.get("sala") or encontrada.get("endereco", "Sala Geral")
        sala = input(f"      Digite a Sala / Ambiente [{sala_padrao}]: ").strip() or sala_padrao
        print(f"{C_VERDE}      Escola: {escola} | Ambiente/Sala: {sala}{C_OFF}")
    else:
        print(f"{C_AMAR}      CIE não encontrado. Digite o CIE, a escola e o ambiente/sala:{C_OFF}")
        cie = input("      Digite o CIE: ").strip() or (cie_input if cie_input else "999999")
        escola = input("      Digite o nome da Escola: ").strip() or "Escola Customizada"
        sala = input("      Digite a Sala / Ambiente / Endereço: ").strip() or "Sala Geral"
        print(f"{C_VERDE}      Vinculada a: {escola} (CIE {cie}) - {sala}{C_OFF}")

    return cie, escola, sala, "ativo"


def executar_ciclo(cfg, banca, simular=False):
    inicio = datetime.now(timezone.utc)

    # ---- 1. coleta ----
    print("\n[1/5] Lendo hardware da maquina...")
    inv = hw.coletar_tudo()
    disco = inv["disco"]

    # Cadeia de identificacao: BIOS -> placa-mae -> disco -> UUID fallback.
    # PC montado (sem fabricante OEM) quase sempre cai para placa-mae ou disco.
    serial = inv["serial_bios"]
    origem = inv.get("origem_serial") or ""
    if not serial:
        serial = disco.get("serial_disco") or ""
        origem = "disco"

    if not serial:
        serial = f"UUID-{uuid.uuid4().hex[:12].upper()}"
        origem = "UUID (fallback)"
        print(f"{C_AMAR}      [AVISO] Nenhum serial de hardware valido. Gerado fallback: {serial}{C_OFF}")

    print(f"      Serial      : {serial}  ({origem})")
    print(f"      Modelo      : {inv['fabricante']} {inv['modelo_pc']}")
    print(f"      CPU         : {inv['cpu']} "
          f"({inv['cpu_cores']}C/{inv['cpu_threads']}T)")
    print(f"      RAM         : {inv['ram_gb']} GB em {inv['ram_pentes']} pente(s)")

    if disco["disponivel"]:
        print(f"      Disco       : {disco['model']} "
              f"({disco['capacity_bytes'] / 1e9:.0f} GB, {disco['tipo_disco']})")
    else:
        print(f"{C_AMAR}      Disco       : SMART indisponivel - {disco['motivo']}{C_OFF}")

    # ---- 2. cadastro / vinculo escolar & avaliacao técnica ----
    cie, escola, sala, status_cadastro = obter_vinculo_escola(serial, simular)

    print("\n      --- Dados de Operação e Avaliação Técnica ---")
    operador_padrao = cfg.get("operador", "Técnico URE")
    operador = input(f"      Nome do Técnico Responsável [{operador_padrao}]: ").strip() or operador_padrao

    print("      Avaliação Técnica do Equipamento:")
    print("        [1] Bom")
    print("        [2] Regular")
    print("        [3] Ruim")
    print("        [4] Defeituoso")
    aval_esc = input("      >>> Escolha a avaliação [1-4, padrão 1]: ").strip()
    mapa_aval = {"1": "Bom", "2": "Regular", "3": "Ruim", "4": "Defeituoso"}
    avaliacao_tecnica = mapa_aval.get(aval_esc, "Bom")
    observacao = input("      Observações (ex: teclas/tela quebrada, teclado USB) [Opcional]: ").strip()
    print(f"      Técnico: {operador} | Avaliação: {avaliacao_tecnica} | Obs: {observacao or '-'}")

    # ---- 3. predicao ----
    print("\n[3/5] Calculando risco de falha do disco...")
    if disco["disponivel"]:
        anterior = None if simular else fb.ultima_leitura(serial)
        risco = prever_risco.calcular_risco(disco, anterior)
        faixa = risco["faixa"]
        cor = COR_FAIXA[faixa]
        print(f"      Risco em {risco['horizonte_dias']} dias : "
              f"{cor}{risco['risco_pct']}%  [{faixa}]{C_OFF}")
        if not risco["tinha_historico"]:
            print(f"{C_CINZA}      (1a leitura desta maquina - sem historico, "
                  f"predicao usa so valores absolutos){C_OFF}")
    else:
        risco = None
        faixa = "OK"
        print(f"{C_CINZA}      Sem SMART, sem predicao.{C_OFF}")

    # ---- 4. sinalizacao fisica ----
    print("\n[4/5] Sinalizando na bancada...")
    estado_led = "QUARENTENA" if status_cadastro == "quarentena" else faixa
    if banca:
        r = banca.sinalizar(estado_led,
                            risco=risco["risco"] if risco else None,
                            serial_maquina=serial)
        print(f"      LED -> {COR_FAIXA[estado_led]}{estado_led}{C_OFF}  "
              f"(resposta: {r})")
    else:
        print(f"{C_CINZA}      Sem Arduino (modo simulacao). LED seria: "
              f"{estado_led}{C_OFF}")

    # ---- 5. nuvem ----
    print("\n[5/5] Enviando para o Firestore...")
    registro = {
        "serial_bios": serial,
        "id_dispositivo": serial,
        "origem_serial": origem,
        "tipo_identificador": origem,
        "hostname": inv.get("hostname", ""),
        "fabricante": inv["fabricante"],
        "modelo_pc": inv["modelo_pc"],
        "sistema_operacional": inv["sistema_operacional"],
        "cpu": inv["cpu"],
        "processador": inv["cpu"],
        "cpu_cores": inv["cpu_cores"],
        "cpu_threads": inv["cpu_threads"],
        "cpu_freq_ghz": inv["cpu_freq_ghz"],
        "ram_gb": inv["ram_gb"],
        "memoria_ram_gb": inv["ram_gb"],
        "ram_pentes": inv["ram_pentes"],
        "pentes": inv["pentes"],
        "disco": disco,
        "risco_falha": risco["risco"] if risco else None,
        "risco_faixa": faixa,
        "status": status_cadastro,
        "status_validacao": status_cadastro,
        "id_bancada": cfg["id_bancada"],
        "ure": cfg["ure"],
        "ure_diretoria": cfg["ure"],
        "operador": operador,
        "tecnico_responsavel": operador,
        "avaliacao_tecnica": avaliacao_tecnica,
        "avaliacao": avaliacao_tecnica,
        "observacoes": observacao,
        "cie": cie,
        "escola": escola,
        "escola_nome": escola,
        "sala": sala,
        "ambiente": sala,
    }

    if simular:
        print(f"{C_CINZA}      Modo simulacao - nada enviado. Registro:{C_OFF}")
        print(json.dumps(registro, indent=2, ensure_ascii=False,
                         default=str)[:900] + " ...")
    else:
        res = fb.salvar_maquina(registro)
        print(f"      {res}")
        if status_cadastro == "quarentena":
            fb.registrar_evento("quarentena", serial,
                                "Maquina desconhecida detectada na bancada")
        if risco and risco["faixa"] == "CRITICO":
            fb.registrar_evento("risco_critico", serial,
                                f"Disco com {risco['risco_pct']}% de risco em "
                                f"{risco['horizonte_dias']} dias",
                                {"risco": risco["risco"]})
        print(f"      Fila offline: {fb.sincronizar_fila()}")

    dur = (datetime.now(timezone.utc) - inicio).total_seconds()
    print(f"\n{'-' * 66}")
    print(f"Ciclo concluido em {dur:.1f}s  |  {serial}  |  "
          f"{COR_FAIXA[estado_led]}{estado_led}{C_OFF}")
    print("-" * 66)
    return registro


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--loop", action="store_true",
                   help="fica em loop; ENTER dispara nova leitura")
    p.add_argument("--simular", action="store_true",
                   help="sem Arduino e sem Firebase")
    p.add_argument("--porta", default=None, help="porta serial (ex: COM3, /dev/ttyUSB0)")
    a = p.parse_args()

    cfg = carregar_config()
    cabecalho(cfg)

    banca = None
    if not a.simular:
        try:
            banca = arduino.Bancada(porta=a.porta or cfg.get("porta_serial"))
            banca.conectar()
            print(f"Arduino  : {banca.id_bancada} (fw {banca.firmware}) "
                  f"em {banca.porta}")
            fb.ping_bancada(banca.id_bancada or cfg["id_bancada"], cfg["ure"])
        except arduino.BancadaNaoEncontrada as e:
            print(f"{C_AMAR}Arduino nao encontrado:{C_OFF}\n{e}")
            print(f"{C_CINZA}Seguindo sem sinalizacao fisica.{C_OFF}")

    try:
        if a.loop:
            print("\nModo bancada. ENTER para ler a maquina conectada, "
                  "Ctrl+C para sair.")
            while True:
                input("\n>>> ENTER para iniciar leitura... ")
                executar_ciclo(cfg, banca, a.simular)
        else:
            executar_ciclo(cfg, banca, a.simular)
    except KeyboardInterrupt:
        print("\nEncerrando.")
    finally:
        if banca:
            banca.fechar()


if __name__ == "__main__":
    sys.exit(main())
