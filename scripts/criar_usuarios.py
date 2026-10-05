"""
criar_usuarios.py
=================
Cria contas de usuário no Firebase Authentication para as escolas cadastradas
e para o administrador da URE, permitindo o login no aplicativo Flutter.

USO:
  python scripts/criar_usuarios.py
"""

import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "bancada"))

import firebase_client as fb
from firebase_admin import auth


def main():
    db = fb.conectar()
    if db is None:
        sys.exit(f"Erro: Não foi possível conectar ao Firebase.\n{fb.motivo_desconexao()}")

    usuarios = [
        {
            "email": "joao@escola.com",
            "senha": "12345678",
            "nome": "EE Prof. Joao (CIE 999001)",
        },
        {
            "email": "maria@escola.com",
            "senha": "12345678",
            "nome": "EE Maria da Silva (CIE 999002)",
        },
        {
            "email": "pedro@escola.com",
            "senha": "12345678",
            "nome": "EE Dom Pedro II (CIE 999003)",
        },
        {
            "email": "admin@ure.gov.br",
            "senha": "12345678",
            "nome": "Administrador URE",
        },
    ]

    print("Criando usuários no Firebase Authentication...\n")
    for u in usuarios:
        try:
            user = auth.create_user(
                email=u["email"],
                password=u["senha"],
                display_name=u["nome"],
            )
            print(f"[OK] Usuário criado: {u['email']} ({u['nome']}) - UID: {user.uid}")
        except Exception as e:
            err_str = str(e)
            if "EMAIL_EXISTS" in err_str or "already exists" in err_str:
                print(f"[!] Usuário já existe: {u['email']}. Atualizando senha...")
                try:
                    user = auth.get_user_by_email(u["email"])
                    auth.update_user(user.uid, password=u["senha"])
                    print(f"[OK] Senha atualizada para: {u['email']}")
                except Exception as ex:
                    print(f"[X] Erro ao atualizar {u['email']}: {ex}")
            else:
                print(f"[X] Erro ao criar {u['email']}: {err_str}")

    print("\n[ok] Concluído! Credenciais prontas para uso no app Flutter.")


if __name__ == "__main__":
    main()
