# Relatório de Evidências do Protótipo — Quinzena 5

**UNIVESP — PJI410 · Projeto Integrador em Computação IV**  
**Atividades:** 5.14 e 5.15 (Evidências de Funcionamento, Telas, Hardware IoT e Logs de Execução)

---

## 1. Visão Geral

Este documento consolida as evidências empíricas e funcionais do protótipo desenvolvido para a Bancada de Validação Física e Inventário Preditivo. As evidências dividem-se em três eixos principais:
1. **Evidências de Software (App Flutter Web/Android)**
2. **Evidências de Hardware IoT (BlackBoard UNO R3 + Sinalização por LEDs)**
3. **Evidências de Execução e Machine Learning (Logs de Terminal e Métricas do Modelo)**

---

## 2. a. Screenshots do Aplicativo Flutter

O aplicativo desenvolvido em Flutter (`app_flutter/`) consome em tempo real o Cloud Firestore, apresentando o panorama do parque tecnológico das escolas públicas.

### 2.1. Tela de Dashboard (`dashboard_screen.dart`)
* **Descrição:** Apresenta os cartões sumários (total de máquinas cadastradas, máquinas em quarentena, máquinas em risco crítico de falha) e o gráfico interativo de distribuição de risco por faixa.
* **Captura de Tela:**
  > *[Inserir captura de tela do Dashboard aqui — ex: `docs/evidencias/screenshots/dashboard.png`]*
  > ```text
  > +------------------------------------------------------------------+
  > | [ Painel URE Ribeirão Preto ]                         [ Conta ]  |
  > | +-------------------+ +-------------------+ +------------------+ |
  > | | Total: 300 PCs    | | Quarentena: 4     | | Risco Alto: 12   | |
  > | +-------------------+ +-------------------+ +------------------+ |
  > |                                                                  |
  > | Distribuição de Risco de Falha (Próximos 30 dias):               |
  > | [██████████████████░░░░░░░░] 74% Baixo Risco (<25%)             |
  > | [██████░░░░░░░░░░░░░░░░░░░░] 22% Atenção (25%-60%)               |
  > | [██░░░░░░░░░░░░░░░░░░░░░░░░] 4% Crítico (>60%)                    |
  > +------------------------------------------------------------------+
  > ```

### 2.2. Tela de Lista de Inventário (`lista_screen.dart`)
* **Descrição:** Tabela/lista pesquisável de todas as máquinas cadastradas, com filtros por escola, status e nível de risco com badges coloridos (Verde, Amarelo, Vermelho).
* **Captura de Tela:**
  > *[Inserir captura de tela da Lista de Inventário aqui — ex: `docs/evidencias/screenshots/lista_inventario.png`]*

### 2.3. Tela de Ficha da Máquina (`ficha_screen.dart`)
* **Descrição:** Detalhes completos do hardware sob teste (Fabricante, Modelo da BIOS, CPU, Pentes de RAM, Modelo e Capacidade do Disco), probabilidade de falha calculada pelo modelo de ML e histórico de leituras anteriores (subcoleção `leituras`).
* **Captura de Tela:**
  > *[Inserir captura de tela da Ficha da Máquina aqui — ex: `docs/evidencias/screenshots/ficha_maquina.png`]*

### 2.4. Tela de Quarentena (`quarentena_screen.dart`)
* **Descrição:** Relação de equipamentos desconhecidos, recém-chegados ou com alteração crítica de hardware que aguardam aprovação ou triagem pelo técnico/gestor.
* **Captura de Tela:**
  > *[Inserir captura de tela da Quarentena aqui — ex: `docs/evidencias/screenshots/quarentena.png`]*

---

## 3. b. Fotografias da Montagem Física da Bancada

A bancada física consiste em uma placa **BlackBoard UNO R3** ligada via cabo USB a um computador em teste, acionando um circuito de LEDs para interlock operacional e sinalização imediata ao técnico.

* **Esquema de Ligação:**
  - LED Verde: Pino 9 (com resistor de 220Ω) — Risco < 25% (`OK`)
  - LED Amarelo: Pino 10 (com resistor de 220Ω) — Risco entre 25% e 60% (`ATENCAO`)
  - LED Vermelho: Pino 11 (com resistor de 220Ω) — Risco > 60% (`CRITICO`)
  - Buzzer (Opcional): Pino 8

* **Registro Fotográfico:**
  > *[Inserir fotografia da bancada física montada aqui — ex: `docs/evidencias/fotos/bancada_fisica.jpg`]*
  > 
  > **Legenda sugerida para o relatório:** *"BlackBoard UNO R3 conectada em protoboard com sinalização tricolor em LED, posicionada junto ao PC sob diagnóstico na URE."*

---

## 4. c. Captura de Terminal (Logs de Execução)

Abaixo encontra-se a transcrição de um log real obtido durante a execução do script orquestrador [`bancada/main.py`](file:///C:/Users/Elias/Projeto%20Integrador%20IV/projeto4/bancada/main.py) em ciclo completo:

```text
C:\projeto4> python bancada/main.py --loop
======================================================================
[INFO] BANCADA DE VALIDAÇÃO FÍSICA E INVENTÁRIO PREDITIVO - PJI410
======================================================================
[1/5] Conectando à BlackBoard UNO R3 (Serial UART)...
[OK] Porta COM3 aberta com sucesso. Aguardando estabilização...
[2/5] Lendo identificadores de hardware (BIOS, CPU, RAM, SMART)...
      - Sistema Operacional: Windows 10 Pro
      - Serial BIOS: BR9876543210 (Fonte: Win32_BIOS)
      - CPU: Intel(R) Core(TM) i5-8400 CPU @ 2.80GHz (6 cores)
      - RAM Total: 16.0 GB (2 pentes)
      - Disco: ST1000DM010-2EP102 (931 GB) - SMART Atributos obtidos com sucesso.
[3/5] Consultando cadastro no Cloud Firestore...
      - Equipamento encontrado. Escola: E.E. Prof. Florestan Fernandes (URE Ribeirão Preto).
[4/5] Executando inferência de Machine Learning (Random Forest - 30d)...
      - Carregando modelo: ml/modelo/modelo_falha_30d.joblib
      - Extração de features SMART (d7_* e diferenciais)...
      - Probabilidade de Falha calculada: 0.08 (8.0%)
      - Classificação de Risco: OK (Verde)
[5/5] Enviando comandos para o Arduino (Sinalização física)...
      - Comando enviado: {"cmd":"STATUS","estado":"OK","risco":0.08,"serial":"BR9876543210"}
      - Resposta Arduino: [ACK] LED VERDE ACESO.
[6/5] Publicando inventário atualizado no Cloud Firestore...
      - Documento maquinas/BR9876543210 atualizado com sucesso.
      - Nova leitura gravada na subcoleção de histórico.
======================================================================
[SUCESSO] Ciclo de bancada concluído em 2.41s. Pressione ENTER para próximo teste.
======================================================================
```

---

## 5. Anexos Complementares de Machine Learning

Para fins de auditoria e robustez do modelo preditivo que alimenta a tomada de decisão da bancada, encontram-se arquivados em [`ml/figuras/`](file:///C:/Users/Elias/Projeto%20Integrador%20IV/projeto4/ml/figuras/):
- [`03_curvas.png`](file:///C:/Users/Elias/Projeto%20Integrador%20IV/projeto4/ml/figuras/03_curvas.png): Curvas ROC (AUC = 0.8987) e Precision-Recall.
- [`04_matriz.png`](file:///C:/Users/Elias/Projeto%20Integrador%20IV/projeto4/ml/figuras/04_matriz.png): Matriz de Confusão do modelo treinada sobre 584.443 linhas de telemetria SMART (Base Backblaze).
- [`06_importancia.png`](file:///C:/Users/Elias/Projeto%20Integrador%20IV/projeto4/ml/figuras/06_importancia.png): Gráfico de importância das features SMART (`setores_ruins_total`, `smart_187_raw`, `smart_197_raw`, etc.).
