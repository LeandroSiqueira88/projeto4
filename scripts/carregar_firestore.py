"""
carregar_firestore.py
=====================
Popula o Firestore com o parque simulado (ml/data/maquinas.csv + bancada/escolas.json),
já com o risco calculado pelo modelo de Machine Learning.

USO:
  python scripts/carregar_firestore.py --por-escola 5          # Gera 510 amostras (5 por escola p/ 102 escolas)
  python scripts/carregar_firestore.py --por-escola 5 --seco   # Simula a geração das 510 amostras sem enviar
  python scripts/carregar_firestore.py --limite 300           # Carga genérica por limite
"""

import argparse
import json
import os
import random
import sys

import pandas as pd

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "bancada"))

import firebase_client as fb          # noqa: E402
import higienizacao                    # noqa: E402
import prever_risco                    # noqa: E402

CSV_MAQ = os.path.join(RAIZ, "ml", "data", "maquinas.csv")
CSV_TEL = os.path.join(RAIZ, "ml", "data", "smart_telemetria.csv.gz")
JSON_ESCOLAS = os.path.join(RAIZ, "bancada", "escolas.json")

SALAS_PADRAO = [
    "Lab. de Informática 01",
    "Lab. de Informática 02",
    "Secretaria",
    "Sala dos Professores",
    "Diretoria / Coordenação",
    "Biblioteca / Sala de Leitura",
]


def carregar_escolas():
    if os.path.exists(JSON_ESCOLAS):
        try:
            with open(JSON_ESCOLAS, encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"Aviso ao carregar escolas.json: {e}")
    return []


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--limite", type=int, default=None,
                   help="limite total de máquinas (legado)")
    p.add_argument("--por-escola", type=int, default=5,
                   help="quantidade de equipamentos por escola (padrão: 5)")
    p.add_argument("--seco", action="store_true", help="não envia ao Firebase, só simula")
    p.add_argument("--quarentena", type=float, default=0.04,
                   help="fração das máquinas que entra em quarentena (padrão 4%%)")
    a = p.parse_args()

    if not os.path.exists(CSV_MAQ):
        sys.exit(f"Faltando {CSV_MAQ}. Rode antes: python ml/gerar_dataset.py")

    print("Lendo dados do dataset e telemetria...")
    maq = pd.read_csv(CSV_MAQ)
    tel = pd.read_csv(CSV_TEL)

    # Última leitura de cada disco
    tel["date"] = pd.to_datetime(tel["date"])
    tel = tel.sort_values("date")
    ultima = tel.groupby("serial_number").tail(1).set_index("serial_number")
    penultima = tel.groupby("serial_number").nth(-2)
    if "serial_number" in penultima.columns:
        penultima = penultima.set_index("serial_number")

    if not a.seco and fb.conectar() is None:
        print("\n[!] ATENÇÃO: Nenhuma credencial ativa do Firebase encontrada em bancada/serviceAccountKey.json.")
        print(fb.motivo_desconexao())
        print("Para enviar os dados ao Firebase, certifique-se de salvar o serviceAccountKey.json na pasta bancada/\n")
        sys.exit(1)

    escolas = carregar_escolas()
    random.seed(42)

    enviados = criticos = atencao = ok_count = quarentenados = 0

    colunas_smart = ["smart_5_raw", "smart_9_raw", "smart_12_raw",
                     "smart_187_raw", "smart_188_raw", "smart_194_raw",
                     "smart_197_raw", "smart_198_raw", "smart_199_raw"]

    idx_maq = 0
    total_maq = len(maq)

    if escolas and a.por_escola is not None and a.por_escola > 0 and a.limite is None:
        print(f"Modo Selecionado: {a.por_escola} equipamentos por escola ({len(escolas)} escolas encontradas no escolas.json)...")
        print(f"Meta de registros: {len(escolas) * a.por_escola} máquinas no total.\n")

        for esc in escolas:
            cie = esc.get("cie", "999999")
            nome_escola = esc.get("escola", "Escola Estadual")

            for i in range(a.por_escola):
                if idx_maq >= total_maq:
                    idx_maq = 0  # Reutiliza base de telemetria com seriais gerados se necessário

                m = maq.iloc[idx_maq]
                idx_maq += 1

                sd = m["serial_disco"]
                u = ultima.loc[sd] if sd in ultima.index else ultima.iloc[idx_maq % len(ultima)]

                leitura = {
                    "disponivel": True,
                    "device": "/dev/sda",
                    "model": u["model"],
                    "serial_disco": f"{sd}_{cie}_{i+1}",
                    "capacity_bytes": int(u["capacity_bytes"]),
                    "tipo_disco": m["tipo_disco"],
                    "smart_ok": True,
                }
                for c in colunas_smart:
                    leitura[c] = int(u[c]) if c in u else 0

                anterior = None
                if sd in penultima.index:
                    pv = penultima.loc[sd]
                    anterior = {c: int(pv[c]) for c in colunas_smart if c in pv}

                risco = prever_risco.calcular_risco(leitura, anterior, dias_entre=1)
                em_quar = random.random() < a.quarentena

                sala = SALAS_PADRAO[i % len(SALAS_PADRAO)]
                serial_bios = f"BR{cie}{i+1:02d}{random.randint(10,99)}"

                registro = {
                    "serial_bios": serial_bios,
                    "id_dispositivo": serial_bios,
                    "origem_serial": "BIOS",
                    "fabricante": "Dell Inc." if i % 2 == 0 else "Lenovo",
                    "modelo_pc": m["modelo_pc"],
                    "sistema_operacional": "Windows 10 Pro 64-bit",
                    "cie": cie,
                    "escola": "" if em_quar else nome_escola,
                    "escola_nome": "" if em_quar else nome_escola,
                    "sala": "" if em_quar else sala,
                    "ambiente": "" if em_quar else sala,
                    "ure": "Ribeirão Preto",
                    "ure_diretoria": "Ribeirão Preto",
                    "cpu": m["cpu"],
                    "processador": m["cpu"],
                    "cpu_cores": int(m["cpu_cores"]),
                    "cpu_threads": int(m["cpu_threads"]),
                    "cpu_freq_ghz": float(m["cpu_freq_ghz"]),
                    "ram_gb": int(m["ram_gb"]),
                    "memoria_ram_gb": int(m["ram_gb"]),
                    "ram_pentes": int(m["ram_pentes"]),
                    "disco": leitura,
                    "risco_falha": risco["risco"],
                    "risco_faixa": risco["faixa"],
                    "status": "quarentena" if em_quar else "ativo",
                    "status_equipamento": "quarentena" if em_quar else "Disponível",
                    "status_visita": "Quarentena" if em_quar else "Concluída",
                    "id_bancada": "URE-01-BANCADA-01",
                    "operador": "carga_inicial",
                    "tecnico_responsavel": "Técnico URE",
                    "avaliacao_tecnica": "Bom",
                }

                registro = higienizacao.higienizar_registro(registro)

                if em_quar:
                    quarentenados += 1
                elif risco["faixa"] == "CRITICO":
                    criticos += 1
                elif risco["faixa"] == "ATENCAO":
                    atencao += 1
                else:
                    ok_count += 1

                if a.seco:
                    if enviados < 5:
                        print(f"  [{enviados+1}] {registro['escola_nome']} ({registro['cie']}) - {registro['ambiente']} | "
                              f"Serial: {registro['serial_bios']} | Risco: {risco['risco_pct']}% [{risco['faixa']}]")
                else:
                    fb.salvar_maquina(registro)
                    if em_quar:
                        fb.registrar_evento("quarentena", registro["serial_bios"],
                                            "Máquina não identificada detectada na bancada")

                enviados += 1
                if enviados % 50 == 0 and not a.seco:
                    print(f"  {enviados} máquinas enviadas ao Firestore...")

    modo = "SIMULADO (modo --seco, nada enviado)" if a.seco else "ENVIADO ao Cloud Firestore"
    print(f"\n=======================================================")
    print(f" Carga concluída: {enviados} máquinas ({modo})")
    print(f" Total de escolas cobertas: {len(escolas)}")
    print(f" Amostras por escola      : {a.por_escola}")
    print(f" Status dos Equipamentos  :")
    print(f"   - Risco Crítico (LED Vermelho) : {criticos}")
    print(f"   - Em Atenção    (LED Amarelo)  : {atencao}")
    print(f"   - OK            (LED Verde)    : {ok_count}")
    print(f"   - Em Quarentena                : {quarentenados}")
    print(f"=======================================================\n")


if __name__ == "__main__":
    main()
