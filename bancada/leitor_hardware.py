"""
leitor_hardware.py
==================
Le a identidade e a saude do hardware da maquina conectada na bancada.

Funciona em Windows (WMI via powershell) e Linux (dmidecode / lscpu).
Os atributos SMART vem do smartctl (pacote smartmontools) nos dois sistemas.

PRECISA DE PRIVILEGIO DE ADMINISTRADOR. Sem isso, serial de BIOS e SMART
retornam vazio. Rode o terminal como administrador / com sudo.

Instalar smartmontools:
  Windows : https://sourceforge.net/projects/smartmontools/  (ou: winget install smartmontools)
  Linux   : sudo apt install smartmontools
  macOS   : brew install smartmontools

Teste rapido:
  python leitor_hardware.py
"""

import json
import platform
import re
import shutil
import socket
import subprocess

SISTEMA = platform.system()  # 'Windows', 'Linux', 'Darwin'

# Mapa: numero do atributo SMART -> nome da coluna usada pelo modelo
SMART_INTERESSE = {
    5: "smart_5_raw",      # setores realocados
    9: "smart_9_raw",      # horas ligado
    12: "smart_12_raw",    # ciclos de energia
    187: "smart_187_raw",  # erros reportados nao corrigiveis
    188: "smart_188_raw",  # command timeout
    194: "smart_194_raw",  # temperatura
    197: "smart_197_raw",  # setores pendentes
    198: "smart_198_raw",  # setores incorrigiveis offline
    199: "smart_199_raw",  # erro CRC UDMA (cabo)
}


def _run(cmd, shell=False):
    """Executa comando e devolve stdout. Devolve '' em qualquer erro."""
    try:
        r = subprocess.run(cmd, shell=shell, capture_output=True,
                           text=True, timeout=45)
        return r.stdout or ""
    except Exception:
        return ""


def _powershell(script):
    return _run(["powershell", "-NoProfile", "-Command", script])


# Valores genericos que fabricantes deixam no campo de serial. Nao servem
# como identificador: varias maquinas diferentes teriam o mesmo.
_SERIAIS_LIXO = {
    "", "to be filled by o.e.m.", "to be filled by o.e.m",
    "default string", "system serial number", "none", "n/a", "na",
    "0", "00000000", "123456789", "not specified", "not applicable",
    "chassis serial number", "empty", "unknown",
}


def _limpar_serial(valor):
    v = (valor or "").strip()
    return "" if v.lower() in _SERIAIS_LIXO else v


# ----------------------------------------------------------------------------
# Identidade da maquina
# ----------------------------------------------------------------------------

def ler_identidade():
    """Serial da BIOS, fabricante e modelo do computador."""
    if SISTEMA == "Windows":
        out = _powershell(
            "Get-CimInstance Win32_BIOS | Select-Object SerialNumber | ConvertTo-Json; "
            "Get-CimInstance Win32_ComputerSystem | "
            "Select-Object Manufacturer,Model | ConvertTo-Json; "
            "Get-CimInstance Win32_BaseBoard | "
            "Select-Object SerialNumber,Product | ConvertTo-Json"
        )
        serial = fabricante = modelo = serial_placa = ""
        blocos = re.findall(r"\{.*?\}", out, re.S)
        for i, bloco in enumerate(blocos):
            try:
                d = json.loads(bloco)
            except Exception:
                continue
            if "Product" in d:  # bloco da placa-mae
                serial_placa = d.get("SerialNumber", "") or ""
                continue
            serial = d.get("SerialNumber", serial) or serial
            fabricante = d.get("Manufacturer", fabricante) or fabricante
            modelo = d.get("Model", modelo) or modelo
    else:
        serial = _run(["dmidecode", "-s", "system-serial-number"]).strip()
        fabricante = _run(["dmidecode", "-s", "system-manufacturer"]).strip()
        modelo = _run(["dmidecode", "-s", "system-product-name"]).strip()
        serial_placa = _run(["dmidecode", "-s", "baseboard-serial-number"]).strip()

    serial = _limpar_serial(serial)
    serial_placa = _limpar_serial(serial_placa)

    # PC montado costuma nao preencher o serial do chassi, mas preenche o da
    # placa-mae. Cadeia de fallback: BIOS -> placa-mae -> (main.py usa o disco)
    origem = "BIOS"
    if not serial and serial_placa:
        serial, origem = serial_placa, "placa-mae"
    elif not serial:
        origem = ""

    return {
        "serial_bios": serial,
        "serial_placa": serial_placa,
        "origem_serial": origem,
        "fabricante": fabricante.strip(),
        "modelo_pc": modelo.strip(),
        "hostname": socket.gethostname(),
    }


# ----------------------------------------------------------------------------
# CPU
# ----------------------------------------------------------------------------

def ler_cpu():
    if SISTEMA == "Windows":
        out = _powershell(
            "Get-CimInstance Win32_Processor | Select-Object "
            "Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | ConvertTo-Json"
        )
        try:
            d = json.loads(out)
            if isinstance(d, list):
                d = d[0]
            return {
                "cpu": (d.get("Name") or "").strip(),
                "cpu_cores": int(d.get("NumberOfCores") or 0),
                "cpu_threads": int(d.get("NumberOfLogicalProcessors") or 0),
                "cpu_freq_ghz": round(float(d.get("MaxClockSpeed") or 0) / 1000, 2),
            }
        except Exception:
            return {"cpu": "", "cpu_cores": 0, "cpu_threads": 0, "cpu_freq_ghz": 0.0}

    out = _run(["lscpu"])
    def campo(rot):
        m = re.search(rot + r":\s*(.+)", out)
        return m.group(1).strip() if m else ""
    try:
        threads = int(campo("CPU\\(s\\)") or 0)
    except ValueError:
        threads = 0
    try:
        por_socket = int(campo("Core\\(s\\) per socket") or 0)
        sockets = int(campo("Socket\\(s\\)") or 1)
        cores = por_socket * sockets
    except ValueError:
        cores = 0
    try:
        freq = round(float(campo("CPU max MHz") or 0) / 1000, 2)
    except ValueError:
        freq = 0.0
    return {"cpu": campo("Model name"), "cpu_cores": cores,
            "cpu_threads": threads, "cpu_freq_ghz": freq}


# ----------------------------------------------------------------------------
# Memoria RAM
# ----------------------------------------------------------------------------

def ler_ram():
    pentes = []
    if SISTEMA == "Windows":
        out = _powershell(
            "Get-CimInstance Win32_PhysicalMemory | Select-Object "
            "Capacity,Speed,Manufacturer,PartNumber,SerialNumber | ConvertTo-Json"
        )
        try:
            d = json.loads(out)
            if isinstance(d, dict):
                d = [d]
            for p in d:
                pentes.append({
                    "capacidade_gb": round(int(p.get("Capacity") or 0) / (1024 ** 3)),
                    "velocidade_mhz": int(p.get("Speed") or 0),
                    "fabricante": (p.get("Manufacturer") or "").strip(),
                    "part_number": (p.get("PartNumber") or "").strip(),
                    "serial": (p.get("SerialNumber") or "").strip(),
                })
        except Exception:
            pass
    else:
        out = _run(["dmidecode", "-t", "memory"])
        for bloco in out.split("Memory Device")[1:]:
            m_cap = re.search(r"Size:\s*(\d+)\s*(MB|GB)", bloco)
            if not m_cap:
                continue
            val, uni = int(m_cap.group(1)), m_cap.group(2)
            gb = val if uni == "GB" else round(val / 1024)
            m_vel = re.search(r"Speed:\s*(\d+)", bloco)
            m_fab = re.search(r"Manufacturer:\s*(.+)", bloco)
            m_ser = re.search(r"Serial Number:\s*(.+)", bloco)
            m_pn = re.search(r"Part Number:\s*(.+)", bloco)
            pentes.append({
                "capacidade_gb": gb,
                "velocidade_mhz": int(m_vel.group(1)) if m_vel else 0,
                "fabricante": m_fab.group(1).strip() if m_fab else "",
                "part_number": m_pn.group(1).strip() if m_pn else "",
                "serial": m_ser.group(1).strip() if m_ser else "",
            })

    return {
        "ram_gb": sum(p["capacidade_gb"] for p in pentes),
        "ram_pentes": len(pentes),
        "pentes": pentes,
    }



# ---------------------------------------------------------------------------
# Normalizacao do valor bruto SMART
# ---------------------------------------------------------------------------
#
# ARMADILHA CLASSICA: o campo raw dos atributos SMART tem 48 bits e varios
# fabricantes empacotam MAIS DE UM contador dentro dele.
#
# Exemplos reais medidos:
#   atributo 194 (temperatura) -> raw.value = 68719476777
#       0x10_0000_0029 = temperatura atual 41 C nos bits baixos,
#       maxima historica nos bits altos.
#   atributo 188 (command timeout) -> raw.value = 65542
#       0x1_0006 = tres contadores de 16 bits concatenados.
#
# Se esse numero cru entrar no modelo, a feature vira lixo de ordem 1e10 e a
# predicao perde o sentido. O proprio smartctl ja resolve isso no campo
# raw.string, que traz o valor que ele exibe na tela. Usar raw.string como
# fonte primaria e cair para o mascaramento de bits so se ele faltar.

_ATRIBUTOS_EMPACOTADOS = {188, 190, 194}  # timeout, airflow temp, temperatura


def _raw_smart(attr):
    """Extrai o valor util do campo raw de um atributo SMART."""
    ident = attr.get("id")
    raw = attr.get("raw") or {}

    # 1a fonte: o texto que o smartctl exibe. Ex: "41 (Min/Max 20/50)" -> 41
    texto = raw.get("string")
    if isinstance(texto, str):
        m = re.search(r"-?\d+", texto)
        if m:
            valor = int(m.group())
            if 0 <= valor < 2 ** 32:
                return valor

    # 2a fonte: valor numerico, mascarando os contadores empacotados
    bruto = int(raw.get("value") or 0)
    if ident in _ATRIBUTOS_EMPACOTADOS:
        bruto &= 0xFFFF          # so os 16 bits baixos importam
    if ident == 194 and bruto > 200:
        bruto &= 0xFF            # temperatura ainda absurda: 8 bits baixos
    return bruto


# ----------------------------------------------------------------------------
# Disco + SMART  (a parte que alimenta o modelo de ML)
# ----------------------------------------------------------------------------

def _capacidade(d):
    """
    Capacidade em bytes. O smartctl nem sempre preenche user_capacity.bytes
    (aconteceu num ST1000DM010 em Windows), entao ha uma cadeia de fallback.
    Capacidade zero quebra a feature capacidade_gb do modelo.
    """
    uc = d.get("user_capacity") or {}
    if uc.get("bytes"):
        return int(uc["bytes"])

    # blocos * tamanho do bloco
    blocos = uc.get("blocks")
    tam = d.get("logical_block_size") or 512
    if blocos:
        return int(blocos) * int(tam)

    if d.get("nvme_total_capacity"):
        return int(d["nvme_total_capacity"])

    # ultimo recurso: extrair do nome comercial ("ST1000DM010" -> 1000 GB)
    nome = (d.get("model_name") or "")
    m = re.search(r"(\d+)\s*TB", nome, re.I)
    if m:
        return int(m.group(1)) * 1_000_000_000_000
    m = re.search(r"[A-Z]{2}(\d{3,4})[A-Z]", nome)
    if m:
        gb = int(m.group(1))
        if 120 <= gb <= 8000:
            return gb * 1_000_000_000

    return 0


def _dispositivos_disco():
    if not shutil.which("smartctl"):
        return []
    out = _run(["smartctl", "--scan"])
    devs = []
    for linha in out.splitlines():
        if linha.strip() and not linha.startswith("#"):
            devs.append(linha.split()[0])
    return devs


def ler_disco(dispositivo=None):
    """
    Devolve dict no formato que prever_risco.calcular_risco() espera.
    Se smartctl nao existir ou nao houver permissao, devolve disponivel=False.
    """
    vazio = {"disponivel": False, "motivo": "", "device": dispositivo or ""}

    if not shutil.which("smartctl"):
        vazio["motivo"] = ("smartctl nao encontrado. Instale smartmontools "
                           "e garanta que esta no PATH.")
        return vazio

    if dispositivo is None:
        devs = _dispositivos_disco()
        if not devs:
            vazio["motivo"] = "Nenhum disco detectado por 'smartctl --scan'."
            return vazio
        dispositivo = devs[0]

    out = _run(["smartctl", "-a", "-j", dispositivo])
    try:
        d = json.loads(out)
    except Exception:
        vazio["device"] = dispositivo
        vazio["motivo"] = ("smartctl nao retornou JSON. Rode como administrador/sudo. "
                           "Em disco USB pode precisar de '-d sat'.")
        return vazio

    dados = {
        "disponivel": True,
        "motivo": "",
        "device": dispositivo,
        "model": (d.get("model_name") or "").strip(),
        "serial_disco": (d.get("serial_number") or "").strip(),
        "capacity_bytes": _capacidade(d),
        "tipo_disco": "SSD" if (d.get("rotation_rate") == 0
                                or d.get("device", {}).get("type") == "nvme") else "HDD",
        "firmware": (d.get("firmware_version") or "").strip(),
        "smart_ok": bool((d.get("smart_status") or {}).get("passed", True)),
    }

    # zera todos os contadores esperados pelo modelo
    for col in SMART_INTERESSE.values():
        dados[col] = 0

    # SATA / HDD: tabela de atributos numerados
    tabela = (d.get("ata_smart_attributes") or {}).get("table") or []
    for attr in tabela:
        col = SMART_INTERESSE.get(attr.get("id"))
        if col:
            dados[col] = _raw_smart(attr)

    # NVMe: nomes diferentes, mapear no equivalente mais proximo
    nvme = d.get("nvme_smart_health_information_log")
    if nvme:
        dados["smart_9_raw"] = int(nvme.get("power_on_hours") or 0)
        dados["smart_12_raw"] = int(nvme.get("power_cycles") or 0)
        dados["smart_194_raw"] = int(nvme.get("temperature") or 0)
        dados["smart_187_raw"] = int(nvme.get("media_errors") or 0)

    # temperatura tambem pode vir num campo dedicado
    if not dados["smart_194_raw"]:
        dados["smart_194_raw"] = int((d.get("temperature") or {}).get("current") or 0)
    if not dados["smart_9_raw"]:
        dados["smart_9_raw"] = int((d.get("power_on_time") or {}).get("hours") or 0)
    if not dados["smart_12_raw"]:
        dados["smart_12_raw"] = int(d.get("power_cycle_count") or 0)

    return dados


# ----------------------------------------------------------------------------
# Coleta completa
# ----------------------------------------------------------------------------

def coletar_tudo():
    inv = {}
    inv.update(ler_identidade())
    inv.update(ler_cpu())
    inv.update(ler_ram())
    inv["disco"] = ler_disco()
    inv["sistema_operacional"] = f"{platform.system()} {platform.release()}"
    return inv


if __name__ == "__main__":
    import pprint
    print(f"Sistema: {SISTEMA}")
    print("Coletando... (pode demorar alguns segundos)\n")
    dados = coletar_tudo()
    pprint.pprint(dados, width=100, sort_dicts=False)

    print("\n--- diagnostico ---")
    if not dados["serial_bios"]:
        print("[!] Serial da BIOS vazio.")
        print("    Causa provavel: falta de privilegio de administrador,")
        print("    ou a placa-mae nao preenche esse campo (comum em PC montado).")
        print("    Plano B: usar o serial do disco como identificador da maquina.")
    else:
        print(f"[ok] Serial da BIOS: {dados['serial_bios']}")

    if not dados["disco"]["disponivel"]:
        print(f"[!] SMART indisponivel: {dados['disco']['motivo']}")
        print("    Sem SMART nao ha predicao de falha. Resolva isso primeiro.")
    else:
        print(f"[ok] SMART lido de {dados['disco']['device']} "
              f"({dados['disco']['model']})")
