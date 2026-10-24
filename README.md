# Bancada de Validação Física e Inventário Preditivo

**UNIVESP — PJI410 · Projeto Integrador em Computação IV**
**Polo: Ribeirão Preto / SP**

Sistema que identifica computadores de escolas públicas em uma bancada física, avalia a saúde do disco com aprendizado de máquina, sinaliza o resultado em LEDs via Arduino e publica o inventário em nuvem, consultável por um app Flutter em tempo real.

---

## 👥 Equipe e Créditos (Grupo de 6 Integrantes)

| Integrante / Aluno(a)       | RA | Polo |
|-----------------------------|---|---|
| Bruno Luiz Rodrigues        | 23211921| Ribeirão Preto / SP |
| Elias Isac de Sousa         | 23201771| Santa Cruz da Esperança/ SP |
| Luis Francisco da Silva Patrocinio Marques Correa    | 2106664| Ribeirão Preto / SP |
| Luis Otavio Nogueira Bortolozzo    | 23205453| Ribeirão Preto / SP |
| Leandro de Caires Siqueira    | 23214764| Ribeirão Preto / SP |
| Ricardo Leal Lencini    | 2321460623214606| Ribeirão Preto / SP |

---

## Como o tema da disciplina é atendido

| Exigência do PJI410 | Onde está no projeto |
|---|---|
| Análise de dados **em escala** | `ml/` — 584 mil linhas de telemetria SMART, 5.000 discos |
| **Aprendizagem de máquina** | Random Forest prevendo falha de disco em 30 dias (ROC AUC 0,90) |
| **IoT** | Arduino UNO na bancada, comunicação serial UART, sinalização física |
| **Nuvem** | Cloud Firestore |
| **Interface de visualização** | App Flutter (Web + Android) |

---

## Estrutura

```
pi4-bancada/
├── README.md
├── .gitignore
├── firestore.rules              regras de segurança do Firestore
├── .vscode/                     extensões e settings recomendados
│
├── docs/
│   └── analise-produto.md       análise de produto, mercado e viabilidade
│
├── ml/                          camada de dados e machine learning
│   ├── requirements.txt
│   ├── gerar_dataset.py         gera a base sintética (schema Backblaze)
│   ├── treinar_modelo.py        treina o Random Forest e salva métricas
│   ├── data/
│   │   ├── smart_telemetria.csv.gz    584.443 linhas · 5.000 discos · 120 dias
│   │   └── maquinas.csv               5.000 PCs da URE
│   └── modelo/
│       ├── modelo_falha_30d.joblib
│       ├── metricas.json
│       └── importancia_features.csv
│
├── bancada/                     script local que roda no PC do técnico
│   ├── requirements.txt
│   ├── config.example.json      copie para config.json e edite
│   ├── main.py                  orquestrador — é o que se executa
│   ├── leitor_hardware.py       BIOS, CPU, RAM, disco + SMART
│   ├── arduino.py               protocolo serial com a BlackBoard
│   ├── prever_risco.py          inferência do modelo
│   └── firebase_client.py       envio ao Firestore + fila offline
│
├── firmware/
│   └── bancada_token/
│       └── bancada_token.ino    firmware C++ do Arduino
│
├── scripts/
│   └── carregar_firestore.py    popula o Firestore com o parque simulado
│
└── app_flutter/
    ├── pubspec.yaml
    ├── README.md
    └── lib/
        ├── main.dart
        ├── models/maquina.dart
        ├── services/firestore_service.dart
        ├── widgets/risco_badge.dart
        └── screens/
            ├── dashboard_screen.dart
            ├── lista_screen.dart
            ├── ficha_screen.dart
            └── quarentena_screen.dart
```

---

## Instalação

### 1. Python

```bash
cd pi4-bancada
python -m venv .venv

# Windows
.venv\Scripts\activate
# Linux / macOS
source .venv/bin/activate

pip install -r ml/requirements.txt
pip install -r bancada/requirements.txt
```

### 2. smartmontools (obrigatório — é a fonte dos dados do modelo)

```bash
# Windows
winget install smartmontools
# depois adicione C:\Program Files\smartmontools\bin ao PATH

# Ubuntu / Debian
sudo apt install smartmontools
```

### 3. Teste imediato, sem hardware nenhum

```bash
python ml/treinar_modelo.py        # retreina e mostra as métricas
python bancada/prever_risco.py     # demonstra a inferência
python bancada/main.py --simular   # ciclo completo sem Arduino e sem Firebase
```

### 4. Arduino

Abra `firmware/bancada_token/bancada_token.ino` na Arduino IDE, selecione a placa Arduino UNO, grave.

Ligação, com resistor de 220 Ω em série em cada LED:

| Componente | Pino |
|---|---|
| LED verde | 9 |
| LED amarelo | 10 |
| LED vermelho | 11 |
| Buzzer (opcional) | 8 |

Teste da comunicação:

```bash
python bancada/arduino.py
```

Deve listar as portas, conectar e percorrer os quatro estados de LED.

### 5. Firebase

1. Crie um projeto em console.firebase.google.com
2. Configurações do projeto → Contas de serviço → Gerar nova chave privada
3. Salve o `.json` baixado como `bancada/serviceAccountKey.json`
4. Publique as regras: `firebase deploy --only firestore:rules`

```bash
cp bancada/config.example.json bancada/config.json   # edite id_bancada e ure
python scripts/carregar_firestore.py --limite 300    # popula o painel
```

### 6. Flutter

```bash
cd app_flutter
flutter create . --platforms=web,android
flutter pub get

dart pub global activate flutterfire_cli
flutterfire configure          # gera lib/firebase_options.dart

flutter run -d chrome
```

Rode primeiro em **Web**. Sem emulador, sem loja, e a banca abre por link.

---

## Uso na bancada

```bash
python bancada/main.py --loop
```

O técnico pluga o PC, aperta ENTER, e o programa:

1. Conecta no Arduino e confirma que a bancada física está presente
2. Lê BIOS, CPU, RAM e os atributos SMART do disco
3. Busca a leitura anterior dessa máquina no Firestore
4. Calcula o risco de falha do disco nos próximos 30 dias
5. Acende o LED — verde, amarelo, vermelho, ou padrão alternado de quarentena
6. Publica o inventário no Firestore

Sem internet, os envios vão para `bancada/fila_offline.jsonl` e sincronizam na próxima execução com rede.

---

## Resultado do modelo

```
584.443 linhas | 5.000 discos | separação treino/teste POR DISCO

ROC AUC : 0,8981
PR AUC  : 0,7462
falha_30d -> precisão 0,79 | recall 0,74 | f1 0,77
```

Top features: `setores_ruins_total`, `d7_smart_187_raw`, `smart_187_raw`, `smart_198_raw`, `smart_197_raw`.

De cada 100 discos marcados como "vai falhar em 30 dias", 79 falham mesmo. E o sistema detecta 74 de cada 100 que de fato falham.

**Detalhe metodológico que vale um parágrafo no relatório:** a separação treino/teste é feita por disco (`GroupShuffleSplit`), não por linha. Se o mesmo disco caísse dos dois lados, o modelo decoraria aquele disco e a métrica subiria falsamente. É o erro mais comum em trabalhos de manutenção preditiva.

**As features `d7_*`** medem a velocidade de degradação nos últimos 7 dias, não o valor absoluto. Por isso a segunda passagem de uma máquina pela bancada prediz muito melhor que a primeira — é o argumento técnico que justifica a bancada existir .

---------

## Dois avisos que precisam constar no relatório

**1. O dataset é sintético.** Foi gerado por simulação em `ml/gerar_dataset.py`, não é medição real. Existe para que todo o pipeline pudesse ser construído e testado sem depender do download de ~10 GB. O schema é idêntico ao Backblaze Hard Drive Test Data, então trocar por dado real é só trocar o arquivo de entrada — o `treinar_modelo.py` não muda uma linha. **Façam essa troca antes da entrega final.**

**2. O Arduino não é autenticação criptográfica.** Ele confirma que existe uma bancada física autorizada conectada e sinaliza o resultado. Como o script roda no PC do técnico, quem tem acesso ao código consegue simular a resposta. O papel real é **interlock operacional e sinalização física** — é assim que deve ser descrito. Chamar de "token de segurança forte" é impreciso e a banca pode questionar.

---

## Divisão de trabalho sugerida

| Frente | Arquivos |
|---|---|
| Hardware e firmware | `firmware/`, `bancada/arduino.py` |
| Coleta e integração | `bancada/leitor_hardware.py`, `bancada/main.py` |
| Dados e ML | `ml/`, `bancada/prever_risco.py` |
| Nuvem e app | `bancada/firebase_client.py`, `app_flutter/`, `firestore.rules` |
