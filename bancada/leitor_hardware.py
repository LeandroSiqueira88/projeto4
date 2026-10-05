"""
leitor_hardware.py
==================
Le a identidade e a saude do hardware da maquina conectada na bancada.
Especializado para inventario URE/FDE.

PRECISA DE PRIVILEGIO DE ADMINISTRADOR.
"""

import json
import platform
import re
import shutil
import socket
import subprocess

SISTEMA = platform.system()

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
    try:
        r = subprocess.run(cmd, shell=shell, capture_output=True, text=True, timeout=45)
        return r.stdout or ""
    except Exception:
        return ""

def _powershell(script):
    return _run(["powershell", "-NoProfile", "-Command", script])

def _limpar_serial(valor):
    v = (valor or "").strip()
    lixo = {"", "to be filled by o.e.m.", "to be filled by o.e.m", "default string",
            "system serial number", "none", "n/a", "0", "not specified"}
    if v.lower() in lixo or "o.e.m." in v.lower():
        return ""
    return v

def ler_identidade():
    """Captura identificadores seguindo regra de fallback URE/FDE."""
    serial = fabricante = modelo = uuid_sistema = mac_address = ""

    if SISTEMA == "Windows":
        out_sys = _powershell(
            "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model | ConvertTo-Json; "
            "Get-CimInstance Win32_ComputerSystemProduct | Select-Object UUID | ConvertTo-Json; "
            "Get-CimInstance Win32_BIOS | Select-Object SerialNumber | ConvertTo-Json; "
            "Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object MacAddress | Select-Object -First 1 | ConvertTo-Json"
        )

        blocos = re.findall(r"\{.*?\}", out_sys, re.S)
        for bloco in blocos:
            try:
                d = json.loads(bloco)
                if "Manufacturer" in d:
                    fabricante = d.get("Manufacturer", "")
                    modelo = d.get("Model", "")
                elif "UUID" in d:
                    uuid_sistema = d.get("UUID", "")
                elif "SerialNumber" in d:
                    serial = d.get("SerialNumber", "")
                elif "MacAddress" in d:
                    mac_address = d.get("MacAddress", "")
            except: continue

    serial_limpo = _limpar_serial(serial)
    tipo_identificador = "SERIAL_BIOS"

    if not serial_limpo:
        serial_limpo = f"UUID:{uuid_sistema}"
        tipo_identificador = "UUID_SISTEMA"

    return {
        "numero_serie": serial_limpo,
        "serial_bios": serial_limpo,
        "tipo_identificador": tipo_identificador,
        "fabricante": fabricante.strip(),
        "modelo": modelo.strip(),
        "modelo_pc": modelo.strip(),
        "hostname": socket.gethostname(),
        "mac_address": mac_address.strip(),
        "sistema_operacional": platform.platform(),
    }

def ler_cpu():
    res = {"processador": "Desconhecido", "cpu": "Desconhecido", "cpu_cores": 4, "cpu_threads": 8, "cpu_freq_ghz": 2.5}
    if SISTEMA == "Windows":
        out = _powershell("Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | ConvertTo-Json")
        try:
            d = json.loads(out)
            item = d[0] if isinstance(d, list) else d
            if item:
                name = (item.get("Name") or "").strip()
                res["processador"] = name
                res["cpu"] = name
                res["cpu_cores"] = int(item.get("NumberOfCores") or 4)
                res["cpu_threads"] = int(item.get("NumberOfLogicalProcessors") or 8)
                mhz = float(item.get("MaxClockSpeed") or 2500)
                res["cpu_freq_ghz"] = round(mhz / 1000.0, 2)
        except: pass
    return res

def ler_ram():
    res = {"memoria_ram_gb": 8.0, "ram_gb": 8.0, "ram_pentes": 1, "pentes": 1}
    if SISTEMA == "Windows":
        out = _powershell("Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity | ConvertTo-Json")
        try:
            d = json.loads(out)
            items = d if isinstance(d, list) else [d]
            total_bytes = sum(int(x.get("Capacity", 0)) for x in items if isinstance(x, dict))
            if total_bytes > 0:
                gb = round(total_bytes / (1024**3), 1)
                res["memoria_ram_gb"] = gb
                res["ram_gb"] = gb
                pentes_count = len(items)
                res["ram_pentes"] = pentes_count
                res["pentes"] = pentes_count
        except: pass
    return res

def _raw_smart(attr):
    raw = attr.get("raw") or {}
    texto = raw.get("string")
    if isinstance(texto, str):
        m = re.search(r"-?\d+", texto)
        if m: return int(m.group())
    return int(raw.get("value") or 0)

def ler_disco():
    """Captura informacoes completas do disco e SMART."""
    disco = {
        "disponivel": False,
        "motivo": "smartctl nao encontrado ou disco nao respondeu",
        "model": "",
        "serial_disco": "",
        "capacity_bytes": 0,
        "tipo_disco": "HDD",
        "smart_ok": True,
    }
    for c in SMART_INTERESSE.values():
        disco[c] = 0

    if shutil.which("smartctl"):
        out_scan = _run(["smartctl", "--scan"])
        devs = [l.split()[0] for l in out_scan.splitlines() if l.strip() and not l.startswith("#")]
        if devs:
            out = _run(["smartctl", "-a", "-j", devs[0]])
            try:
                d = json.loads(out)
                disco["disponivel"] = True
                disco["motivo"] = ""
                disco["model"] = d.get("model_name") or d.get("model") or d.get("product") or ""
                disco["serial_disco"] = d.get("serial_number") or ""
                cap = (d.get("user_capacity") or {}).get("bytes") or (d.get("capacity") or {}).get("bytes") or 0
                disco["capacity_bytes"] = int(cap)
                disco["smart_ok"] = bool((d.get("smart_status") or {}).get("passed", True))

                model_upper = disco["model"].upper()
                if any(x in model_upper for x in ["SSD", "NVME", "KINGSTON", "WDS"]):
                    disco["tipo_disco"] = "SSD"
                else:
                    disco["tipo_disco"] = "HDD"

                tabela = (d.get("ata_smart_attributes") or {}).get("table") or []
                for attr in tabela:
                    col = SMART_INTERESSE.get(attr.get("id"))
                    if col:
                        disco[col] = _raw_smart(attr)
                return disco
            except Exception as e:
                disco["motivo"] = f"Erro no parsing smartctl: {e}"

    # Fallback WMI no Windows
    if SISTEMA == "Windows":
        out = _powershell("Get-PhysicalDisk | Select-Object FriendlyName,MediaType,Size,SerialNumber | Select-Object -First 1 | ConvertTo-Json")
        try:
            d = json.loads(out)
            if d:
                disco["disponivel"] = True
                disco["motivo"] = ""
                disco["model"] = d.get("FriendlyName", "")
                disco["tipo_disco"] = d.get("MediaType", "HDD")
                disco["capacity_bytes"] = int(d.get("Size", 0))
                disco["serial_disco"] = d.get("SerialNumber", "").strip()
                return disco
        except Exception as e:
            if not disco["motivo"] or disco["motivo"].startswith("smartctl"):
                disco["motivo"] = f"WMI indisponivel: {e}"

    return disco

def coletar_tudo():
    dados = {}
    dados.update(ler_identidade())
    dados.update(ler_cpu())
    dados.update(ler_ram())

    disco = ler_disco()
    dados["disco"] = disco
    dados["modelo_disco"] = disco["model"]
    dados["tipo_disco"] = disco["tipo_disco"]
    dados["capacidade_disco_gb"] = round(disco["capacity_bytes"] / (1024**3), 1)
    dados["smart"] = {k: v for k, v in disco.items() if k.startswith("smart_") or k == "smart_ok"}

    return dados
