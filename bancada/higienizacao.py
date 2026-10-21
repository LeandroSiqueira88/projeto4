"""
higienizacao.py
===============
Módulo utilitário dedicado à higienização e padronização de dados de inventário
(remoção de caracteres especiais em excesso, padronização em caixa-alta/Title Case,
limpeza de espaços em branco e tratamento de serial numbers).
"""

import re


def limpar_string(valor, maiuscula=True):
    """Remove espaços excessivos e normaliza texto."""
    if not valor or not isinstance(valor, str):
        return str(valor) if valor is not None else ""

    texto = re.sub(r'\s+', ' ', valor).strip()
    return texto.upper() if maiuscula else texto


def limpar_titulo(valor):
    """Padroniza nomes próprios (escolas, salas) em Title Case com limpeza de espaços."""
    if not valor or not isinstance(valor, str):
        return str(valor) if valor is not None else ""
    texto = re.sub(r'\s+', ' ', valor).strip()
    return texto.title()


def higienizar_serial(serial):
    """Higieniza número de série (remove espaços, caracteres especiais perigosos e bota em maiúscula)."""
    if not serial:
        return ""
    # Mantém apenas alfanuméricos, hifens e underscores
    limpo = re.sub(r'[^A-Z0-9\-_]', '', str(serial).upper())
    return limpo


def higienizar_registro(registro):
    """
    Higieniza um dicionário completo de registro de máquina antes de enviar
    ao Firestore ou salvar no dataset.
    """
    if not isinstance(registro, dict):
        return registro

    reg = dict(registro)

    # Campos de identificação (seriais, CIE)
    for campo in ["serial_bios", "id_dispositivo", "serial_disco", "cie", "origem_serial", "tipo_identificador"]:
        if campo in reg and reg[campo]:
            reg[campo] = higienizar_serial(reg[campo])

    # Campos descritivos de hardware e operacionais em caixa-alta
    for campo in ["fabricante", "modelo_pc", "sistema_operacional", "cpu", "processador", "tipo_disco", "operador", "tecnico_responsavel"]:
        if campo in reg and reg[campo]:
            reg[campo] = limpar_string(reg[campo], maiuscula=True)

    # Campos de localização e diretoria em Title Case
    for campo in ["escola", "escola_nome", "sala", "ambiente", "ure", "ure_diretoria"]:
        if campo in reg and reg[campo]:
            reg[campo] = limpar_titulo(reg[campo])

    # Observações e texto livre (limpeza de espaços múltiplos)
    if "observacoes" in reg and reg["observacoes"]:
        reg["observacoes"] = re.sub(r'\s+', ' ', str(reg["observacoes"])).strip()

    # Tratamento de dicionário de disco aninhado
    if "disco" in reg and isinstance(reg["disco"], dict):
        disco = dict(reg["disco"])
        if "model" in disco and disco["model"]:
            disco["model"] = limpar_string(disco["model"], maiuscula=True)
        if "serial_disco" in disco and disco["serial_disco"]:
            disco["serial_disco"] = higienizar_serial(disco["serial_disco"])
        reg["disco"] = disco

    return reg
