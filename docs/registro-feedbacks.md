# Registro de Feedbacks da Comunidade Externa — Validação com Gestores Escolares

**UNIVESP — PJI410 · Projeto Integrador em Computação IV**  
**Atividade:** 5.16 (Registro de Feedbacks e Validação com a Comunidade Externa / Escolas Públicas de Ribeirão Preto/SP)

---

## 1. Contexto da Validação e Cronograma

Como parte do ciclo de desenvolvimento e validação do protótipo na **Quinzena 5**, a equipe conduziu sessões formais de demonstração da solução **Bancada de Validação Física e Inventário Preditivo** com profissionais da educação pública, técnicos de suporte de unidades escolares e gestores educacionais.

* **Período de Realização:** Outubro / Novembro (Quinzena 5)
* **Local das Sessões:** Núcleo de Tecnologia Educacional (NTE) e laboratórios de informática de escolas públicas estaduais parceiras em **Ribeirão Preto/SP**.
* **Objetivo:** Expor o fluxo real do protótipo (hardware IoT BlackBoard UNO R3 + script local + modelo de Machine Learning + painel web em Flutter) para coletar impressões de usabilidade, validar requisitos operacionais e registrar apontamentos para o aprimoramento da ferramenta.

---

## 2. Perfil dos Participantes Ouvidos

Participaram das sessões de validação 5 profissionais com atuação direta na gestão de ativos e suporte tecnológico escolar:

| Participante | Perfil / Cargo | Local / Unidade |
| :--- | :--- | :--- |
| **Participante 01** | Técnico de Suporte de Campo | Núcleo Regional de Suporte de TI / Ribeirão Preto |
| **Participante 02** | Coordenador de Tecnologia Educacional | Diretoria de Ensino da Região de Ribeirão Preto |
| **Participante 03** | Diretor de Escola | E.E. Prof. Florestan Fernandes |
| **Participante 04** | Vice-Diretor / Gestor Administrativo | E.E. Dr. Guimarães Junior |
| **Participante 05** | Professor Coordenador de Laboratório (PCL) | E.E. Jardim Antártica |

---

## 3. Roteiro da Sessão de Demonstração

Cada sessão teve duração aproximada de 25 minutos, estruturada em três momentos:
1. **Contextualização (5 min):** Apresentação das dores atuais (controle de inventário em planilhas desatualizadas, falta de histórico de peças e trocas reativas que paralisam laboratórios).
2. **Demonstração Prática da Bancada (10 min):** Conexão de um computador de laboratório à placa BlackBoard UNO R3 via USB, execução do script de leitura de hardware e visualização da resposta física imediata através dos LEDs (Verde para máquina OK, Amarelo para atenção, Vermelho para crítico, Alternado para quarentena).
3. **Apresentação do Painel em Nuvem (10 min):** Navegação pelo app Flutter Web demonstrando o recebimento em tempo real dos dados no Cloud Firestore, os alertas de risco de falha de disco em 30 dias (ML) e a gestão da tela de quarentena.

---

## 4. Apontamentos, Validações e Feedbacks Obtidos

Os apontamentos colhidos foram agrupados por eixos temáticos:

### Eixo A: Usabilidade e Utilidade da Bancada Física (IoT + LEDs)
* **Validação:** Os técnicos de suporte enfatizaram que a indicação visual direta por LED na bancada agiliza o diagnóstico em massa de computadores recolhidos para manutenção, permitindo saber o estado do equipamento sem precisar abrir terminais ou relatórios longos.
* **Sugestão de Melhoria:** Adicionar um sinal sonoro curto (buzzer) para diferenciar distintamente o status `OK` do status `CRITICO`, auxiliando em ambientes de oficina com ruído operacional.

### Eixo B: Confiabilidade do Inventário de Hardware
* **Validação:** A extração automatizada de seriais da BIOS e de atributos SMART foi elogiada por eliminar erros humanos e fraudes/trocas não registradas de peças entre laboratórios.
* **Sugestão de Melhoria:** Alinhamento com a realidade das escolas públicas, onde muitos computadores são montados por licitação sem preenchimento correto do serial na BIOS. A estratégia adotada no código de fallback (placa-mãe e disco) foi validada como imprescindível.

### Eixo C: Predição de Falhas de Disco (Machine Learning)
* **Validação:** Os diretores e coordenadores destacaram o valor estratégico do modelo preditivo (risco de falha em 30 dias). Prever a pane de um disco rígido antes que o aluno perca seus arquivos ou que a aula seja cancelada representa ganho operacional direto.
* **Sugestão de Melhoria:** Solicitação de um recurso de exportação de relatório (ex: formato PDF) contendo a listagem de máquinas em risco crítico para anexar aos pedidos de reposição de peças enviados à Secretaria da Educação.

### Eixo D: Controle de Quarentena
* **Validação:** O conceito de quarentena para máquinas desconhecidas ou transferidas sem baixa foi considerado excelente para o controle patrimonial das escolas públicas de Ribeirão Preto.

---

## 5. Conclusão e Ações Incorporadas

A validação com a comunidade externa na Quinzena 5 confirmou que a proposta tecnológica atende a uma dor real e urgente da rede pública. As sugestões práticas (como o refinamento do fallback de hardware e o direcionamento para relatórios gerenciais) foram integradas ao escopo de evolução do projeto.
