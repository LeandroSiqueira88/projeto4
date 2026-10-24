"""
carregar_firestore.py
=====================
Popula o Firestore com o parque simulado (ml/data/maquinas.csv), ja com o risco
calculado pelo modelo. Serve para o app Flutter ter dado para mostrar antes de a
bancada fisica estar pronta.

USO:
  python scripts/carregar_firestore.py --limite 300
  python scripts/carregar_firestore.py --limite 300 --seco   # so mostra, nao envia

Rode com --limite. O plano gratuito do Firebase (Spark) tem cota diaria de
escrita; carregar 5.000 maquinas de uma vez queima a cota. 200-400 e o bastante
para o painel ficar convincente na apresentacao.
"""

import argparse
import os
import random
import sys

import pandas as pd

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "bancada"))

import firebase_client as fb          # noqa: E402
import prever_risco                    # noqa: E402

CSV_MAQ = os.path.join(RAIZ, "ml", "data", "maquinas.csv")
CSV_TEL = os.path.join(RAIZ, "ml", "data", "smart_telemetria.csv.gz")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--limite", type=int, default=300)
    p.add_argument("--seco", action="store_true", help="nao envia, so mostra")
    p.add_argument("--quarentena", type=float, default=0.06,
                   help="fracao que entra como quarentena (default 6%%)")
    a = p.parse_args()

    if not os.path.exists(CSV_MAQ):
        sys.exit(f"Faltando {CSV_MAQ}. Rode antes: python ml/gerar_dataset.py")

    print("lendo dados...")
    maq = pd.read_csv(CSV_MAQ).head(a.limite)
    tel = pd.read_csv(CSV_TEL)

    # ultima leitura de cada disco
    tel["date"] = pd.to_datetime(tel["date"])
    tel = tel.sort_values("date")
    ultima = tel.groupby("serial_number").tail(1).set_index("serial_number")
    penultima = tel.groupby("serial_number").nth(-2)
    if "serial_number" in penultima.columns:
        penultima = penultima.set_index("serial_number")

    if not a.seco and fb.conectar() is None:
        sys.exit(f"Sem credencial do Firebase. Esperada em bancada/serviceAccountKey.json\n"
                 f"Use --seco para testar sem enviar.")

    random.seed(42)
    enviados = criticos = quarentenados = 0

    for _, m in maq.iterrows():
        sd = m["serial_disco"]
        if sd not in ultima.index:
            continue
        u = ultima.loc[sd]

        colunas_smart = ["smart_5_raw", "smart_9_raw", "smart_12_raw",
                         "smart_187_raw", "smart_188_raw", "smart_194_raw",
                         "smart_197_raw", "smart_198_raw", "smart_199_raw"]

        leitura = {
            "disponivel": True,
            "device": "/dev/sda",
            "model": u["model"],
            "serial_disco": sd,
            "capacity_bytes": int(u["capacity_bytes"]),
            "tipo_disco": m["tipo_disco"],
            "smart_ok": True,
        }
        for c in colunas_smart:
            leitura[c] = int(u[c])

        anterior = None
        if sd in penultima.index:
            pv = penultima.loc[sd]
            anterior = {c: int(pv[c]) for c in colunas_smart}

        risco = prever_risco.calcular_risco(leitura, anterior, dias_entre=1)
        em_quar = random.random() < a.quarentena

        registro = {
            "serial_bios": m["serial_bios"],
            "origem_serial": "BIOS",
            "fabricante": "Dell Inc.",
            "modelo_pc": m["modelo_pc"],
            "sistema_operacional": "Windows 10",
            "escola": "" if em_quar else m["escola"],
            "sala": "" if em_quar else m["sala"],
            "cpu": m["cpu"], "cpu_cores": int(m["cpu_cores"]),
            "cpu_threads": int(m["cpu_threads"]),
            "cpu_freq_ghz": float(m["cpu_freq_ghz"]),
            "ram_gb": int(m["ram_gb"]), "ram_pentes": int(m["ram_pentes"]),
            "pentes": [],
            "disco": leitura,
            "risco_falha": risco["risco"],
            "risco_faixa": risco["faixa"],
            "status": "quarentena" if em_quar else "ativo",
            "id_bancada": "URE-01-BANCADA-01",
            "ure": "URE Exemplo",
            "operador": "carga_inicial",
        }

        if risco["faixa"] == "CRITICO":
            criticos += 1
        if em_quar:
            quarentenados += 1

        if a.seco:
            if enviados < 3:
                print(f"  {registro['serial_bios']}  risco={risco['risco_pct']}%  "
                      f"{risco['faixa']}  status={registro['status']}")
        else:
            fb.salvar_maquina(registro)
            if em_quar:
                fb.registrar_evento("quarentena", m["serial_bios"],
                                    "Maquina desconhecida detectada na bancada")
        enviados += 1
        if enviados % 50 == 0 and not a.seco:
            print(f"  {enviados} enviadas...")

    modo = "SIMULADO (nada enviado)" if a.seco else "enviado ao Firestore"
    print(f"\n{enviados} maquinas {modo}")
    print(f"  risco critico : {criticos}")
    print(f"  quarentena    : {quarentenados}")


if __name__ == "__main__":
    main()
