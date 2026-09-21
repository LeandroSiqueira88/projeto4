# Fluxo de informação do sistema

Documento de referência para a equipe. Explica, do início ao fim, como o dado sai do computador da escola e chega ao painel do gestor.

---

## O princípio que organiza tudo

**O computador é a fonte dos dados. O Arduino é periférico. O Firebase é depósito. O app é vitrine.**

Essa ordem importa porque é contraintuitiva. A impressão natural é que o Arduino "captura" a informação e manda para o sistema. Não é o que acontece, e não pode ser — por uma razão física, não de projeto.

O serial da BIOS, o modelo do processador, os pentes de memória e os atributos SMART do disco existem **dentro** do PC. Quem os lê é o sistema operacional, através de chamadas ao firmware e ao controlador do disco. Um Arduino conectado por USB não é visto pelo PC como algo que possa consultá-lo: ele aparece como uma porta serial, um periférico. A relação é o inverso — o PC comanda o Arduino.

Isso vale também com Wi-Fi. O ESP8266 resolve **transmissão**, não **acesso**. Ele continua sem conseguir ler o disco do computador.

---

## As cinco etapas

O que segue é o que `bancada/main.py` executa, em ordem. Rodando o script você vê exatamente essas etapas numeradas no terminal.

### Etapa 1 — Leitura do hardware

Arquivo: `bancada/leitor_hardware.py`

O script identifica o sistema operacional e usa o método adequado:

- **Windows** — PowerShell consultando WMI (`Win32_BIOS`, `Win32_Processor`, `Win32_PhysicalMemory`, `Win32_BaseBoard`)
- **Linux** — `dmidecode` e `lscpu`
- **Ambos** — `smartctl` (pacote smartmontools) para os atributos SMART do disco

Exige privilégio de administrador. Sem isso, serial da BIOS e SMART retornam vazios.

**Cadeia de identificação.** O sistema tenta três fontes, nessa ordem:

1. Serial da BIOS
2. Serial da placa-mãe
3. Serial do disco

PCs de marca (Dell, Positivo) preenchem a BIOS. PCs montados frequentemente não — e caem para placa-mãe. O serial do disco é último recurso, porque trocar o HD mudaria a identidade da máquina.

O script também descarta valores genéricos que fabricantes deixam no campo: `To be filled by O.E.M.`, `Default string`, `System Serial Number`. Se vários equipamentos compartilhassem esse valor, o inventário colapsaria.

**Uma armadilha real encontrada durante o desenvolvimento.** O campo `raw` dos atributos SMART tem 48 bits, e vários fabricantes empacotam mais de um contador nele. O atributo 194 (temperatura) chegou a retornar `68719476777` — a temperatura atual nos bits baixos, a máxima histórica nos altos. Esse número entrava direto no modelo como se fosse graus Celsius. A correção lê o campo `raw.string`, que é o valor que o próprio `smartctl` exibe, e cai para mascaramento de bits quando ele falta.

### Etapa 2 — Consulta ao cadastro

Arquivo: `bancada/firebase_client.py`, função `buscar_maquina`

O script consulta o Firestore pelo identificador obtido. Dois desfechos:

- **Encontrou** — máquina conhecida, segue o fluxo normal
- **Não encontrou** — status `quarentena`

Quarentena não significa defeito. Significa máquina não identificada: equipamento novo, transferido sem registro, com placa-mãe trocada, ou que não deveria estar ali.

### Etapa 3 — Predição de risco

Arquivo: `bancada/prever_risco.py`

Carrega `ml/modelo/modelo_falha_30d.joblib` e aplica sobre os atributos SMART lidos. Devolve a probabilidade de falha do disco nos próximos 30 dias.

**Por que o script busca a leitura anterior.** Contadores SMART são cumulativos — nunca diminuem. Um disco com 400 setores realocados há três anos é menos preocupante que um que tinha zero na semana passada e tem cinquenta agora. As features `d7_*` medem essa velocidade de degradação, comparando a leitura atual com a anterior guardada no Firestore.

Na primeira passagem de uma máquina não existe comparação, e essas variáveis entram zeradas. A predição fica mais fraca. Da segunda em diante, melhora.

**Ressalva honesta:** essa hipótese se confirmou nos dados sintéticos, onde as features `d7_*` ficaram entre as mais importantes do modelo. Nos dados reais da Backblaze, elas saíram do top 8. A explicação provável é que datacenters trocam discos antes da degradação progredir. Está documentado em `docs/validacao-dados-reais.md`.

### Etapa 4 — Sinalização física

Arquivo: `bancada/arduino.py` + `firmware/bancada_token/bancada_token.ino`

O script abre a porta serial e envia uma linha JSON:

```json
{"cmd":"STATUS","estado":"CRITICO","risco":0.82,"serial":"BR123"}
```

O firmware lê a linha, interpreta e acende o LED:

| Estado | LED | Significado |
|---|---|---|
| `OK` | Verde | Risco abaixo de 25% |
| `ATENCAO` | Amarelo | Entre 25% e 60% |
| `CRITICO` | Vermelho piscando | Acima de 60% |
| `QUARENTENA` | Vermelho/amarelo alternando | Máquina não identificada |

O Arduino responde confirmando. Se não houver placa conectada, o script avisa e segue sem sinalização — o ciclo não é interrompido.

**Detalhe de implementação:** o firmware não usa biblioteca de JSON. O UNO tem 2 KB de RAM, e as mensagens são simples o bastante para busca de substring, que é mais leve e não quebra.

### Etapa 5 — Envio para a nuvem

Arquivo: `bancada/firebase_client.py`

O script monta o registro completo e grava no Firestore:

```
maquinas/{serial}
  ├── identificação: serial, fabricante, modelo, origem do serial
  ├── hardware: cpu, cores, ram_gb, pentes
  ├── disco: modelo, capacidade, tipo, atributos SMART
  ├── risco_falha: 0.0 a 1.0
  ├── status: ativo | quarentena | descartado
  ├── atualizado_em: timestamp
  └── leituras/{timestamp}    ← subcoleção, histórico completo
```

O documento principal é sobrescrito a cada leitura. A subcoleção `leituras` acumula o histórico — é ela que alimenta o gráfico de evolução e a busca pela leitura anterior da etapa 3.

**Modo offline.** Sem internet, o envio vai para `bancada/fila_offline.jsonl` e sincroniza na próxima execução com rede. Escola pública cai da rede com frequência; isso não é enfeite.

---

## Como o app recebe

O aplicativo Flutter **não** conversa com o script nem com o Arduino. Ele lê o Firestore, e só.

`lib/services/firestore_service.dart` abre streams do Firestore. Stream é uma consulta que permanece aberta: quando o script grava um documento, o Firestore empurra a mudança para todos os clientes conectados, e a tela se redesenha sozinha. Não há botão de atualizar nem polling.

Na prática: com o painel aberto no navegador, rodar `python bancada/main.py` faz a máquina aparecer na tela em poucos segundos.

---

## As duas credenciais, e por que são diferentes

Esta parte costuma confundir.

**O script da bancada** usa `bancada/serviceAccountKey.json`, uma credencial de conta de serviço (Admin SDK). Ela tem acesso total e **ignora as regras de segurança por design**. É o script que grava telemetria e risco.

**O aplicativo** usa autenticação por e-mail e senha, e está sujeito às regras em `firestore.rules`. Ele pode:

- ler tudo
- alterar apenas `status`, `escola`, `sala` e os campos de baixa
- apagar registros

Ele **não pode** criar máquinas nem alterar telemetria ou risco. Isso garante que todo equipamento no inventário passou por uma leitura real de hardware, e que ninguém forja um risco pelo app.

Cada pessoa gera a própria chave de serviço. Ela nunca é compartilhada e está no `.gitignore`.

---

## Sobre a observação de segurança

A crítica levantada está correta e merece registro explícito:

> "Isso ainda não afeta em segurança, porque de qualquer forma eu posso só rodar o script dele e encaminhar qualquer coisa, e aí não farei a bancada que eu montei no kit."

Exatamente isso. O script roda no computador do técnico. Quem controla o script pode:

- ignorar o Arduino e enviar ao Firebase mesmo assim
- modificar o código para forjar a resposta da placa
- escrever outro script que grave diretamente no Firestore

O Arduino **não** impede nenhuma dessas coisas. Ele não assina nada, não guarda segredo, não valida criptograficamente. A troca de mensagens é JSON em texto puro sobre serial.

**Portanto o Arduino não deve ser descrito como "token de segurança" no relatório.** Se a banca perguntar, a resposta honesta é:

> O Arduino cumpre função de **interlock operacional e sinalização física**. Ele confirma que existe uma bancada autorizada conectada e comunica o resultado ao técnico por LED, sem exigir que ele leia a tela. Não é um mecanismo de autenticação: como o script executa no computador do operador, quem tem acesso ao código pode contorná-lo. A segurança efetiva do sistema está nas regras do Firestore e na separação de credenciais.

Essa resposta é mais forte que a alternativa. Reconhecer o limite de uma escolha de projeto demonstra compreensão; afirmar segurança que não existe é o que uma banca atenta derruba.

**O que tornaria a validação real**, se o grupo quiser evoluir: gravar uma chave secreta no Arduino e implementar desafio-resposta com HMAC-SHA256. O PC envia um nonce, a placa devolve o HMAC dos dados com a chave, e o Firebase (via Cloud Function) valida a assinatura. Aí sim o Arduino seria necessário, porque a chave nunca sairia dele. Fora do escopo deste semestre, mas é a resposta técnica correta para "como fazer de verdade".

---

## Onde o Wi-Fi do kit rende

O ESP8266 não substitui o computador, mas tem um uso que fortalece o projeto: **transformar a bancada em fonte própria de dados**.

Um sensor DHT22 (temperatura e umidade, cerca de R$ 20) ou ACS712 (corrente) publicando no Firebase periodicamente adiciona:

- série temporal capturada por sensor, não derivada do PC
- monitoramento das condições do laboratório — calor acelera degradação de disco
- correlação possível entre temperatura da sala e risco das máquinas daquela sala

Isso atende a parte "dados capturados por IoT" do enunciado de forma mais substancial que um LED.

**Mas é evolução, não substituição.** Sem os LEDs funcionando, não há bancada.

---

## Para testar cada etapa isoladamente

```bash
# Etapa 1 — leitura de hardware (precisa de administrador)
python bancada/leitor_hardware.py

# Etapa 3 — predição, com dados de exemplo
python bancada/prever_risco.py

# Etapa 4 — comunicação serial e LEDs (só precisa da placa)
python bancada/arduino.py

# Etapas 2 e 5 — conexão com o Firestore
python bancada/firebase_client.py

# Ciclo completo
python bancada/main.py

# Ciclo completo sem Arduino e sem Firebase
python bancada/main.py --simular
```

O teste da etapa 4 não depende do modelo de ML nem do Firebase. Quem tem a placa consegue validar a parte física sem configurar mais nada.
