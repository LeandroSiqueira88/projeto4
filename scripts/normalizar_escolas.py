import json
import os

path = os.path.join("bancada", "escolas.json")
if not os.path.exists(path):
    print(f"Arquivo não encontrado: {path}")
    exit(1)

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

novo_data = []
for item in data:
    cie = str(item.get("Código CIE") or item.get("cie") or "")
    escola = item.get("Escola") or item.get("escola") or ""
    endereco = item.get("Endereço Localizado") or item.get("endereco") or "Endereço não informado"
    sala = item.get("sala") or "Sala Geral"

    novo_data.append({
        "cie": cie,
        "escola": escola,
        "endereco": endereco,
        "sala": sala
    })

with open(path, "w", encoding="utf-8") as f:
    json.dump(novo_data, f, indent=2, ensure_ascii=False)

print(f"Sucesso! {len(novo_data)} escolas normalizadas e formatadas com indentação em {path}")
