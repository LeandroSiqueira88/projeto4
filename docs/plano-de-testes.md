# Plano de Testes e Casos de Uso — Bancada de Validação Física e Inventário Preditivo

**UNIVESP — PJI410 · Projeto Integrador em Computação IV**  
**Documento de Referência:** Quinzena 5 (Atividades 5.12 e 5.13)

---

## 1. Introdução

Este documento estabelece o plano formal de testes e casos de uso para a validação integrada do sistema composto por:
1. **Hardware IoT (BlackBoard UNO R3 + LEDs + Buzzer)** conectado via UART/USB.
2. **Script de Orquestração Local em Python** (leitura de hardware, SMART, Machine Learning e cliente Firebase).
3. **Banco de Dados em Nuvem (Cloud Firestore)**.
4. **Aplicativo Multiplataforma (Flutter Web/Android)**.

O objetivo é garantir o correto funcionamento de ponta a ponta (end-to-end), cobrindo desde a coleta física no computador sob teste até a visualização gerencial no painel.

---

## 2. Ambiente de Testes

- **Hardware:** BlackBoard UNO R3 (ATmega328P), LEDs (Verde, Amarelo, Vermelho), resistores de 220Ω, cabo USB.
- **Computador Testado / Técnico:** Windows 10/11 ou Linux (Ubuntu/Debian) com privilégios de Administrador / Root, `smartmontools` (`smartctl`) instalado e adicionado ao PATH.
- **Ambiente de Software:** Python 3.10+, Bibliotecas (`pyserial`, `scikit-learn`, `pandas`, `firebase-admin`), Flutter SDK (Web/Android), Projeto Firebase configurado com Firestore.

---

## 3. Casos de Teste (CT01 a CT06)

### CT01 — Leitura de Hardware e Atributos SMART
* **ID:** `CT01`
* **Objetivo:** Validar se o script local consegue extrair com precisão a identidade do computador (serial da BIOS/placa-mãe, CPU, RAM) e os atributos SMART do disco rígido/SSD.
* **Cenário:** Bancada IoT / Script Local (`bancada/leitor_hardware.py`)
* **Pré-condições:** 
  - Execução do terminal com privilégios de Administrador.
  - `smartmontools` instalado e operacional no sistema.
* **Passos de Execução:**
  1. Abrir o terminal na raiz do projeto.
  2. Ativar o ambiente virtual Python (`.venv\Scripts\activate` ou `source .venv/bin/activate`).
  3. Executar o comando: `python bancada/leitor_hardware.py`
* **Resultado Esperado:** 
  - O console deve exibir em formato JSON ou estruturado os dados da BIOS (ou placa-mãe/disco como fallback), especificações de CPU, quantidade de RAM e uma lista detalhada dos atributos SMART do disco (ex: SMART 5, 9, 187, 194, 197, 198) sem erros de permissão.

---

### CT02 — Handshake Serial e Sinalização Física com Arduino
* **ID:** `CT02`
* **Objetivo:** Verificar a comunicação serial UART entre o script Python e a BlackBoard UNO R3, bem como o correto acionamento dos LEDs correspondentes ao estado de saúde da máquina.
* **Cenário:** Bancada IoT / Firmware (`firmware/bancada_token/bancada_token.ino` e `bancada/arduino.py`)
* **Pré-condições:**
  - BlackBoard UNO R3 conectada via USB a uma porta COM válida.
  - Firmware gravado na placa.
* **Passos de Execução:**
  1. Executar o teste de comunicação serial: `python bancada/arduino.py`
  2. Observar o comportamento físico da placa e a resposta no terminal.
* **Resultado Esperado:**
  - O script identifica automaticamente a porta serial da placa.
  - A placa percorre os estados programados: LED Verde (`OK`), Amarelo (`ATENCAO`), Vermelho piscando (`CRITICO`) e Alternado (`QUARENTENA`).
  - O terminal exibe a confirmação de handshake bem-sucedido.

---

### CT03 — Inferência do Modelo de Machine Learning (Risco de Falha em 30 Dias)
* **ID:** `CT03`
* **Objetivo:** Validar se o modelo Random Forest treinado (`ml/modelo/modelo_falha_30d.joblib`) processa corretamente os atributos SMART lidos e retorna uma probabilidade confiável de falha (0.0 a 1.0).
* **Cenário:** Camada de Machine Learning (`bancada/prever_risco.py`)
* **Pré-condições:**
  - Dataset treinado e arquivo `.joblib` presente em `ml/modelo/`.
* **Passos de Execução:**
  1. Executar o script de inferência isolada: `python bancada/prever_risco.py`
* **Resultado Esperado:**
  - O sistema carrega o modelo sem falhas.
  - A partir dos dados SMART fornecidos, o script calcula e imprime no terminal a probabilidade de falha (ex: `Risco de falha em 30d: 0.12 (OK)` ou `0.85 (CRITICO)`).

---

### CT04 — Sincronização, Persistência em Nuvem e Modo Offline
* **ID:** `CT04`
* **Objetivo:** Garantir que o inventário e o risco calculado sejam gravados com sucesso no Cloud Firestore e que, na ausência de conexão com a internet, os dados sejam armazenados em fila local para sincronização posterior.
* **Cenário:** Nuvem / Sincronização (`bancada/firebase_client.py`)
* **Pré-condições:**
  - Arquivo `serviceAccountKey.json` configurado em `bancada/`.
  - Conexão com a internet ativa (para teste online) ou desativada (para teste offline).
* **Passos de Execução:**
  1. Executar o ciclo completo da bancada: `python bancada/main.py`
  2. Simular queda de rede (ou desconectar a internet) e executar novamente o script.
* **Resultado Esperado:**
  - **Online:** O documento da máquina é atualizado na coleção `maquinas/{serial}` e o histórico é gravado na subcoleção `leituras`.
  - **Offline:** O script detecta a falha de conexão, grava o pacote em `bancada/fila_offline.jsonl` sem interromper o fluxo da bancada, e sincroniza automaticamente assim que a conexão é restabelecida.

---

### CT05 — Visualização em Tempo Real no App Flutter (Dashboard e Ficha)
* **ID:** `CT05`
* **Objetivo:** Validar se o aplicativo Flutter (Web / Android) consome em tempo real as alterações do Firestore e exibe corretamente os indicadores de risco, gráficos e fichas das máquinas.
* **Cenário:** Aplicativo Cliente (`app_flutter/`)
* **Pré-condições:**
  - Flutter SDK instalado.
  - Arquivo `lib/firebase_options.dart` configurado.
* **Passos de Execução:**
  1. Iniciar o app no navegador: `cd app_flutter && flutter run -d chrome`
  2. Executar o script de bancada (`python bancada/main.py`) para uma máquina de teste.
  3. Observar a tela do aplicativo em tempo real.
* **Resultado Esperado:**
  - O dashboard atualiza os contadores de máquinas ativas, em atenção, em risco crítico e em quarentena sem necessidade de recarregar a página (streams do Firestore).
  - A lista exibe a máquina com o badge de risco correto (Verde/Amarelo/Vermelho).
  - Ao clicar na máquina, a ficha detalha o hardware completo e o histórico de leituras.

---

### CT06 — Tratamento de Máquinas Desconhecidas (Fluxo de Quarentena)
* **ID:** `CT06`
* **Objetivo:** Validar o comportamento do sistema quando um computador nunca antes inventariado (ou com serial alterado/não cadastrado) é plugado na bancada.
* **Cenário:** Integração Bancada + Nuvem + App (`quarentena_screen.dart`)
* **Pré-condições:**
  - Máquina com serial inexistente na base do Firestore.
* **Passos de Execução:**
  1. Conectar a nova máquina na bancada e executar `python bancada/main.py`.
  2. Verificar a sinalização física no Arduino.
  3. Acessar a tela de Quarentena no app Flutter.
* **Resultado Esperado:**
  - O Arduino sinaliza o estado de Quarentena (LEDs vermelho e amarelo alternando).
  - O registro é enviado ao Firestore com status `quarentena`.
  - A tela de Quarentena no app exibe o equipamento pendente de aprovação/vinculação pelo gestor.

---

## 4. Matriz de Rastreabilidade de Testes

| ID do Caso de Teste | Componente / Camada | Requisito / Atividade PJI410 | Status Esperado |
| :--- | :--- | :--- | :--- |
| **CT01** | Hardware / SO | Leitura de Atributos SMART & BIOS | Aprovado |
| **CT02** | IoT / Firmware | Interlock e Sinalização Física (LEDs) | Aprovado |
| **CT03** | Machine Learning | Classificação Random Forest (30d) | Aprovado |
| **CT04** | Nuvem / Firestore | Persistência e Fila Offline | Aprovado |
| **CT05** | App Flutter | Visualização em Tempo Real (Streams) | Aprovado |
| **CT06** | Gestão de Ativos | Tratamento de Quarentena | Aprovado |
