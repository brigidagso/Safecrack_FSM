Máquina de estados finitos (FSM) que implementa um cofre digital de senha numérica, desenvolvida em SystemVerilog para FPGA. O usuário monta uma senha de 4 dígitos, um dígito por vez, usando botões para incrementar, decrementar e confirmar cada posição. Ao confirmar os quatro dígitos, o circuito compara a senha digitada com a senha correta e sinaliza o resultado por LEDs.

## Visão geral

- Entrada de senha **dígito a dígito** (estilo cadeado), de 0 a 9 por posição.
- Comparação com a senha correta fixa em **`1-2-3-4`**.
- Feedback visual em tempo real nos displays de 7 segmentos.
- Resultado sinalizado por LEDs verdes (acesso liberado) ou vermelhos (acesso negado), com retorno automático ao estado inicial após um tempo definido.
- Tratamento de *bouncing* dos botões (debounce) e detecção de borda para garantir uma ação por clique.

## Hardware alvo

- **Placa:** Altera/Intel DE2-115 (FPGA Cyclone IV).
- **Clock:** 50 MHz.
- **Ferramenta de síntese:** Intel Quartus Prime.

## Mapeamento de I/O

| Sinal      | Função                                                        |
|------------|---------------------------------------------------------------|
| `KEY[0]`   | Reset (ativo em nível baixo) — reinicia o sistema             |
| `KEY[1]`   | Confirma o dígito atual e avança de posição                   |
| `KEY[2]`   | Incrementa o dígito da posição atual (com *wrap-around* 9→0)  |
| `KEY[3]`   | Decrementa o dígito da posição atual (com *wrap-around* 0→9)  |
| `HEX3..HEX0` | Exibem os 4 dígitos da senha (HEX3 = 1º dígito)             |
| `HEX4`     | Exibe a posição atual sendo editada (de 1 a 4)                |
| `LEDG`     | Acende (verde) no estado `COFRE_ABERTO`                       |
| `LEDR`     | Acende (vermelho) no estado `ACESSO_NEGADO`                   |

> Os botões `KEY` da DE2-115 são ativos em nível baixo: valem `1` quando soltos e `0` quando pressionados.

## Como usar

1. Pressione `KEY[0]` para resetar. Os displays mostram `0 0 0 0` e a posição `1` no `HEX4`.
2. Ajuste o primeiro dígito com `KEY[2]` (sobe) e `KEY[3]` (desce).
3. Pressione `KEY[1]` para confirmar e avançar para o próximo dígito.
4. Repita os passos 2 e 3 para os quatro dígitos.
5. Ao confirmar o quarto dígito, o circuito verifica a senha:
   - **Correta:** LEDs verdes acendem por ~5 segundos.
   - **Incorreta:** LEDs vermelhos acendem por ~3 segundos.
6. Após o tempo de sinalização, o sistema volta sozinho ao estado inicial, pronto para uma nova tentativa.

## Arquitetura da máquina de estados

O comportamento é modelado em 8 estados:

| Estado            | Descrição                                                       |
|-------------------|----------------------------------------------------------------|
| `INICIAL`         | Zera senha, índice e timer; segue para a espera                |
| `AGUARDA_BOTAO`   | Estado central: aguarda o usuário pressionar um botão          |
| `INCREMENTA`      | Aumenta o dígito da posição atual e volta a aguardar           |
| `DECREMENTA`      | Diminui o dígito da posição atual e volta a aguardar           |
| `CONFIRMA`        | Confirma o dígito; avança a posição ou vai para a verificação  |
| `VERIFICAR_SENHA` | Compara a senha digitada com `1-2-3-4`                          |
| `COFRE_ABERTO`    | Senha correta: acende LEDs verdes por ~5 s e reinicia          |
| `ACESSO_NEGADO`   | Senha incorreta: acende LEDs vermelhos por ~3 s e reinicia     |

Fluxo resumido: `INICIAL → AGUARDA_BOTAO →` (`INCREMENTA` / `DECREMENTA` / `CONFIRMA`) `→ ... → VERIFICAR_SENHA →` (`COFRE_ABERTO` / `ACESSO_NEGADO`) `→ INICIAL`.

## Detalhes de implementação

**Padrão de FSM (`estado` / `prox_estado`).** A lógica é separada em dois blocos sequenciais (`always_ff`) que apenas registram valores na borda do clock, e um bloco combinacional (`always_comb`) que calcula o próximo valor de cada registrador. Essa separação evita estados instáveis e *latches* indesejados.

**Temporização por contagem de ciclos.** Como em hardware o tempo é medido em ciclos de clock, os atrasos são definidos como constantes: `TIME_5SEC = 250_000_000` e `TIME_3SEC = 150_000_000` ciclos, equivalentes a 5 s e 3 s a 50 MHz.

**Debounce dos botões.** Cada botão tem um contador que só valida uma mudança de estado depois que a leitura crua permanece estável por `DEBOUNCE_MAX` ciclos, filtrando o ruído mecânico do contato.

**Detecção de borda.** As expressões do tipo `key_old & ~key_db` produzem um pulso de um único ciclo no instante em que o botão é pressionado, garantindo uma ação por clique mesmo que o botão seja mantido pressionado.

**Displays de 7 segmentos.** A função `sseg_decode` converte um dígito (0–9) no padrão de segmentos correspondente. Na DE2-115 os displays usam lógica invertida (bit `0` acende o segmento). O `HEX4` exibe `idx + 1` para mostrar a posição de 1 a 4.

## Como compilar e gravar

1. Abra o projeto no Intel Quartus Prime e adicione `safecrackpro_fsm.sv`.
2. Defina `safecrackpro_fsm` como *top-level entity*.
3. Faça as atribuições de pinos (*Pin Assignments*) conforme o manual da DE2-115 para `clk`, `KEY`, `HEX0..HEX4`, `LEDG` e `LEDR`.
4. Compile o projeto (*Start Compilation*).
5. Conecte a placa e grave via *Programmer* (arquivo `.sof`).

## Estrutura de arquivos

```
.
├── safecrackpro_fsm.sv   # Módulo principal (FSM, debounce, displays)
└── README.md             # Este arquivo
```

## Parâmetros configuráveis

- `CLK_FREQ` — frequência do clock (padrão 50 MHz).
- `TIME_5SEC` / `TIME_3SEC` — duração das sinalizações de acesso liberado/negado.
- `DEBOUNCE_MAX` — janela de debounce dos botões.
- Senha correta — definida diretamente no estado `VERIFICAR_SENHA` (atualmente `1-2-3-4`).

## Possíveis melhorias

- Tornar a senha configurável (por *switches* ou um modo de cadastro) em vez de fixa no código.
- Adicionar contagem de tentativas e bloqueio temporário após erros consecutivos.
- Bancada de testes (*testbench*) para simulação antes da gravação na placa.

## Autores

Projeto acadêmico de Sistemas Digitais desenvolvido em grupo.
