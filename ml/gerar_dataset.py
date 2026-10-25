"""
gerar_dataset.py
================
Gera um dataset SINTETICO de telemetria SMART de discos, com schema compativel
com o Backblaze Hard Drive Test Data (https://www.backblaze.com/cloud-storage/resources/hard-drive-test-data).

Saidas:
  data/smart_telemetria.csv.gz  -> serie temporal diaria por disco (dado de treino)
  data/maquinas.csv             -> inventario de PCs da URE (liga PC ao disco)

Uso:
  python gerar_dataset.py
  python gerar_dataset.py --discos 500 --dias 120 --seed 42
"""

import argparse
import json
import os
from datetime import date, timedelta

import numpy as np
import pandas as pd

MODELOS = [
    ("ST500LM012 HN",   500_107_862_016, 0.22, 0.145),
    ("WDC WD5000AAKX",  500_107_862_016, 0.18, 0.061),
    ("ST1000DM003",   1_000_204_886_016, 0.20, 0.098),
    ("HGST HTS541010", 1_000_204_886_016, 0.12, 0.035),
    ("TOSHIBA DT01ACA", 1_000_204_886_016, 0.10, 0.072),
    ("Kingston SA400S37", 480_103_981_056, 0.10, 0.018),
    ("WDC WDS240G2G0A",  240_057_409_536, 0.08, 0.021),
]

CPUS = [
    ("Intel Core i3-4130", 2, 4, 3.40), ("Intel Core i5-4570", 4, 4, 3.20),
    ("Intel Core i5-2400", 4, 4, 3.10), ("Intel Core i7-3770", 4, 8, 3.40),
    ("Intel Pentium G3220", 2, 2, 3.00), ("AMD Ryzen 3 2200G", 4, 4, 3.50),
    ("Intel Celeron J1800", 2, 2, 2.41), ("Intel Core i5-8400", 6, 6, 2.80),
]


def _serial(rng, prefixo, n=8):
    alfabeto = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return prefixo + "".join(rng.choice(list(alfabeto), size=n))


def gerar(n_discos=500, n_dias=120, seed=42):
    rng = np.random.default_rng(seed)
    data_fim = date.today()
    data_ini = data_fim - timedelta(days=n_dias - 1)
    datas = [data_ini + timedelta(days=i) for i in range(n_dias)]

    # Carregar escolas de bancada/escolas.json (5 maquinas por escola)
    escolas_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bancada", "escolas.json")
    lista_escolas = []
    if os.path.exists(escolas_path):
        with open(escolas_path, encoding="utf-8") as f:
            escolas_raw = json.load(f)
            # 100 escolas x 5 maquinas = 500 maquinas
            lista_escolas = escolas_raw[: max(1, n_discos // 5)]

    if not lista_escolas:
        lista_escolas = [{"escola": "EE Exemplo", "sala": "Laboratorio 1", "cie": "999000"}]

    pesos = np.array([m[2] for m in MODELOS], dtype=float)
    pesos /= pesos.sum()

    linhas = []
    maquinas = []

    for i in range(n_discos):
        mi = rng.choice(len(MODELOS), p=pesos)
        modelo, capacidade, _, taxa_anual = MODELOS[mi]
        eh_ssd = "SSD" in modelo or "Kingston" in modelo or "WDS" in modelo

        serial_disco = _serial(rng, "S")
        serial_bios = _serial(rng, "BR", 9)

        idade_anos = rng.gamma(shape=2.6, scale=1.5)
        idade_anos = float(np.clip(idade_anos, 0.05, 11.0))
        horas_ini = idade_anos * 365 * 24 * rng.uniform(0.28, 0.55)

        mult_idade = 1.0 + max(0.0, idade_anos - 3.5) ** 1.7 * 0.55
        p_falha_janela = 1 - np.exp(-taxa_anual * mult_idade * (n_dias / 365.0))
        vai_falhar = rng.random() < p_falha_janela

        if vai_falhar:
            dia_falha = int(rng.integers(int(n_dias * 0.20), n_dias))
            dur_degrad = int(np.clip(rng.gamma(3.0, 9.0), 3, 75))
            dia_degrad = max(0, dia_falha - dur_degrad)
        else:
            dia_falha = None
            dia_degrad = None
            dur_degrad = None

        base_5 = int(rng.poisson(0.7 * mult_idade)) if not eh_ssd else 0
        base_197 = 0
        base_187 = int(rng.poisson(0.25 * mult_idade)) if not eh_ssd else 0
        base_198 = 0
        base_199 = int(rng.poisson(0.5))
        base_188 = int(rng.poisson(0.3 * mult_idade)) if not eh_ssd else 0
        ciclos_ini = int(horas_ini / rng.uniform(5.5, 11.0))
        lbas_ini = float(horas_ini * rng.uniform(1.2e6, 6.0e6))
        temp_base = rng.uniform(28, 38) + (2.5 if not eh_ssd else 0)

        s5, s197, s187, s198, s199, s188 = base_5, base_197, base_187, base_198, base_199, base_188

        dia_fim_disco = dia_falha if dia_falha is not None else n_dias - 1

        for d in range(dia_fim_disco + 1):
            ligado_hoje = rng.random() < 0.72
            horas = horas_ini + d * rng.uniform(4.5, 7.5) if ligado_hoje else horas_ini + d * 5.0

            if dia_degrad is not None and d >= dia_degrad:
                prog = (d - dia_degrad) / max(1, (dia_falha - dia_degrad))
                prog = float(np.clip(prog, 0, 1))
                if eh_ssd:
                    s187 += rng.poisson(0.8 + 9 * prog ** 2)
                    s198 += rng.poisson(0.3 + 4 * prog ** 2)
                else:
                    s5 += rng.poisson(0.6 + 34 * prog ** 2.2)
                    s197 += rng.poisson(0.4 + 22 * prog ** 2.0)
                    s187 += rng.poisson(0.3 + 14 * prog ** 2.0)
                    s198 += rng.poisson(0.2 + 11 * prog ** 2.3)
                    s188 += rng.poisson(0.2 + 5 * prog ** 1.8)
                temp = temp_base + 4.5 * prog + rng.normal(0, 1.6)
            else:
                if not eh_ssd and rng.random() < 0.012:
                    s5 += rng.poisson(1)
                if rng.random() < 0.010:
                    s199 += rng.poisson(1)
                if not eh_ssd and rng.random() < 0.006:
                    s188 += 1
                temp = temp_base + rng.normal(0, 1.5)

            falhou = 1 if (dia_falha is not None and d == dia_falha) else 0

            linhas.append((
                datas[d].isoformat(),
                serial_disco,
                modelo,
                capacidade,
                falhou,
                int(s5),
                int(round(horas)),
                int(ciclos_ini + d // 1),
                int(s187),
                int(s188),
                int(round(np.clip(temp, 18, 78))),
                int(s197),
                int(s198),
                int(s199),
                float(lbas_ini + d * rng.uniform(0.8e6, 5.0e6)),
            ))

        escola_obj = lista_escolas[(i // 5) % len(lista_escolas)]
        escola_nome = escola_obj.get("escola", "Escola Exemplo")
        sala_nome = escola_obj.get("sala", "Laboratorio 1")
        cie_escola = escola_obj.get("cie", "000000")

        cpu, cores, threads, freq = CPUS[rng.integers(len(CPUS))]
        maquinas.append((
            serial_bios,
            serial_disco,
            escola_nome,
            sala_nome,
            cie_escola,
            f"Dell OptiPlex {rng.choice(['3020','3040','7010','9020'])}",
            cpu, int(cores), int(threads), float(freq),
            int(rng.choice([2, 4, 4, 8, 8, 16], p=[.12, .28, .18, .22, .12, .08])),
            int(rng.choice([1, 2, 2, 4], p=[.35, .40, .15, .10])),
            modelo,
            int(capacidade),
            "SSD" if eh_ssd else "HDD",
            round(float(idade_anos), 2),
            "ativo",
        ))

    df = pd.DataFrame(linhas, columns=[
        "date", "serial_number", "model", "capacity_bytes", "failure",
        "smart_5_raw", "smart_9_raw", "smart_12_raw", "smart_187_raw",
        "smart_188_raw", "smart_194_raw", "smart_197_raw", "smart_198_raw",
        "smart_199_raw", "smart_241_raw",
    ])

    dfm = pd.DataFrame(maquinas, columns=[
        "serial_bios", "serial_disco", "escola", "sala", "cie", "modelo_pc",
        "cpu", "cpu_cores", "cpu_threads", "cpu_freq_ghz",
        "ram_gb", "ram_pentes", "modelo_disco", "capacidade_bytes",
        "tipo_disco", "idade_anos", "status",
    ])

    return df, dfm


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--discos", type=int, default=500)
    p.add_argument("--dias", type=int, default=120)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--saida", type=str, default=None)
    a = p.parse_args()

    if a.saida is None:
        a.saida = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

    os.makedirs(a.saida, exist_ok=True)
    df, dfm = gerar(a.discos, a.dias, a.seed)

    f_tel = os.path.join(a.saida, "smart_telemetria.csv.gz")
    f_maq = os.path.join(a.saida, "maquinas.csv")
    df.to_csv(f_tel, index=False, compression="gzip")
    dfm.to_csv(f_maq, index=False)

    n_falhas = int(df["failure"].sum())
    print(f"telemetria : {len(df):,} linhas | {df['serial_number'].nunique():,} discos")
    print(f"falhas     : {n_falhas:,} discos ({n_falhas/df['serial_number'].nunique()*100:.2f}% do parque)")
    print(f"gravado    : {f_tel}")
    print(f"gravado    : {f_maq}")


if __name__ == "__main__":
    main()
