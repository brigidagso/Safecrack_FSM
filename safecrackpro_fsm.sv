//=============================================================================
// safecrackpro_fsm
//-----------------------------------------------------------------------------
// Cofre eletrônico controlado por máquina de estados (FSM).
// O usuário monta uma senha de 4 dígitos (0–9) usando 3 botões:
//   - KEY[3] decrementa o dígito atual
//   - KEY[2] incrementa o dígito atual
//   - KEY[1] confirma o dígito e avança para o próximo
// Após confirmar os 4 dígitos, a senha é comparada com a senha fixa "1234".
//   - Senha correta  -> COFRE_ABERTO  (LEDs verdes acesos por 5 s)
//   - Senha errada   -> ACESSO_NEGADO (LEDs vermelhos acesos por 3 s)
// KEY[0] é o reset assíncrono (ativo em nível baixo).
//
// Displays:
//   HEX3..HEX0 = dígitos 0..3 da senha
//   HEX4       = índice do dígito sendo editado (mostra 1..4)
//=============================================================================
module safecrackpro_fsm #(
    parameter int CLK_FREQ = 50000000   // Frequência do clock (50 MHz na DE2)
)(
    input  logic clk,
    input  logic [3:0] KEY,             // Botões da placa (ativos em nível baixo)

    output logic [6:0] HEX0,            // Displays de 7 segmentos
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,

    output logic [8:0] LEDG,            // LEDs verdes (cofre aberto)
    output logic [17:0] LEDR            // LEDs vermelhos (acesso negado)
);

    //-------------------------------------------------------------------------
    // Constantes de tempo (em ciclos de clock) e debounce.
    // Com 50 MHz, 1 segundo = 50.000.000 ciclos.
    //-------------------------------------------------------------------------
    localparam int TIME_5SEC = 250000000;   // 5 s -> tempo de cofre aberto
    localparam int TIME_3SEC = 150000000;   // 3 s -> tempo de acesso negado
    localparam int DEBOUNCE_MAX = 1000000;  // ~20 ms de filtro de debounce

    //-------------------------------------------------------------------------
    // Estados da FSM.
    //-------------------------------------------------------------------------
    typedef enum logic [2:0] {
        INICIAL,         // Zera tudo e parte para a espera de botão
        AGUARDA_BOTAO,   // Espera o usuário apertar inc/dec/confirma
        DECREMENTA,      // Diminui o dígito atual
        INCREMENTA,      // Aumenta o dígito atual
        CONFIRMA,        // Avança o índice; no 4º dígito vai verificar
        VERIFICAR_SENHA, // Compara a senha digitada com a senha fixa
        COFRE_ABERTO,    // Senha correta
        ACESSO_NEGADO    // Senha incorreta
    } state_t;

    state_t estado, prox_estado;        // Estado atual e próximo estado

    //-------------------------------------------------------------------------
    // Reset assíncrono ativo em baixo, mapeado em KEY[0].
    //-------------------------------------------------------------------------
    logic rstn;
    assign rstn = KEY[0];

    //-------------------------------------------------------------------------
    // Registradores de dados da FSM.
    //-------------------------------------------------------------------------
    logic [3:0] senha [0:3];            // Os 4 dígitos da senha (valor atual)
    logic [3:0] prox_senha [0:3];       // Próximo valor de cada dígito

    logic [1:0] idx, prox_idx;          // Índice do dígito sendo editado (0..3)
    logic [31:0] timer, prox_timer;     // Contador de tempo (cofre/negado)

    //-------------------------------------------------------------------------
    // Sinais de debounce dos botões.
    //   keyX_db  = valor "limpo" (debounced) do botão
    //   keyX_old = valor do botão no ciclo anterior (p/ detectar borda)
    //   cntX     = contador de estabilidade do filtro de debounce
    //-------------------------------------------------------------------------
    logic key1_db, key2_db, key3_db;
    logic key1_old, key2_old, key3_old;
    logic [19:0] cnt1, cnt2, cnt3;

    //-------------------------------------------------------------------------
    // Pulsos de "apertou" (duram 1 ciclo de clock).
    // Como os botões são ativos em baixo, o aperto corresponde à borda de
    // descida do sinal debounced: estava 1 (solto) e agora é 0 (apertado).
    //   keyX_old & ~keyX_db  ==  1 só no exato ciclo do aperto.
    //-------------------------------------------------------------------------
    logic confirmar;
    logic incrementar;
    logic decrementar;

    assign confirmar   = key1_old & ~key1_db;   // KEY[1]
    assign incrementar = key2_old & ~key2_db;   // KEY[2]
    assign decrementar = key3_old & ~key3_db;   // KEY[3]

    //=========================================================================
    // BLOCO 1: Debounce dos botões (lógica sequencial).
    // Um botão só tem seu valor atualizado quando permanece diferente do valor
    // atual por DEBOUNCE_MAX ciclos seguidos; qualquer oscilação reinicia o
    // contador. Também guarda o valor anterior (keyX_old) para gerar os pulsos.
    //=========================================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            // No reset, botões "soltos" (nível alto) e contadores zerados.
            key1_db <= 1'b1;
            key2_db <= 1'b1;
            key3_db <= 1'b1;

            key1_old <= 1'b1;
            key2_old <= 1'b1;
            key3_old <= 1'b1;

            cnt1 <= 20'd0;
            cnt2 <= 20'd0;
            cnt3 <= 20'd0;
        end else begin
            // Memoriza o valor debounced anterior (usado para detectar borda).
            key1_old <= key1_db;
            key2_old <= key2_db;
            key3_old <= key3_db;

            // --- Debounce KEY[1] (confirmar) ---
            if (KEY[1] != key1_db) begin
                if (cnt1 >= DEBOUNCE_MAX) begin
                    key1_db <= KEY[1];      // Estável o suficiente: aceita
                    cnt1 <= 20'd0;
                end else begin
                    cnt1 <= cnt1 + 20'd1;   // Ainda contando estabilidade
                end
            end else begin
                cnt1 <= 20'd0;              // Valor igual ao atual: reinicia
            end

            // --- Debounce KEY[2] (incrementar) ---
            if (KEY[2] != key2_db) begin
                if (cnt2 >= DEBOUNCE_MAX) begin
                    key2_db <= KEY[2];
                    cnt2 <= 20'd0;
                end else begin
                    cnt2 <= cnt2 + 20'd1;
                end
            end else begin
                cnt2 <= 20'd0;
            end

            // --- Debounce KEY[3] (decrementar) ---
            if (KEY[3] != key3_db) begin
                if (cnt3 >= DEBOUNCE_MAX) begin
                    key3_db <= KEY[3];
                    cnt3 <= 20'd0;
                end else begin
                    cnt3 <= cnt3 + 20'd1;
                end
            end else begin
                cnt3 <= 20'd0;
            end
        end
    end

    //=========================================================================
    // BLOCO 2: Registradores de estado (lógica sequencial).
    // A cada borda de clock, copia os valores "prox_*" para os registradores
    // reais. É aqui que a FSM efetivamente avança de estado.
    //=========================================================================
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            estado <= INICIAL;
            idx <= 2'd0;
            timer <= 32'd0;

            senha[0] <= 4'd0;
            senha[1] <= 4'd0;
            senha[2] <= 4'd0;
            senha[3] <= 4'd0;
        end else begin
            estado <= prox_estado;
            idx <= prox_idx;
            timer <= prox_timer;

            senha[0] <= prox_senha[0];
            senha[1] <= prox_senha[1];
            senha[2] <= prox_senha[2];
            senha[3] <= prox_senha[3];
        end
    end

    //=========================================================================
    // BLOCO 3: Lógica combinacional de próximo estado e próximos dados.
    // Calcula prox_estado / prox_idx / prox_timer / prox_senha a partir do
    // estado atual e das entradas. Não cria registradores: tudo aqui é
    // recalculado de forma puramente combinacional.
    //=========================================================================
    always_comb begin
        // Por padrão, "manter o valor atual" — evita latches inferidos.
        prox_estado = estado;
        prox_idx = idx;
        prox_timer = timer;

        prox_senha[0] = senha[0];
        prox_senha[1] = senha[1];
        prox_senha[2] = senha[2];
        prox_senha[3] = senha[3];

        case (estado)

            // Estado de reinício lógico: zera índice, timer e senha.
            INICIAL: begin
                prox_idx = 2'd0;
                prox_timer = 32'd0;

                prox_senha[0] = 4'd0;
                prox_senha[1] = 4'd0;
                prox_senha[2] = 4'd0;
                prox_senha[3] = 4'd0;

                prox_estado = AGUARDA_BOTAO;
            end

            // Espera um pulso de botão; cada pulso dura 1 ciclo, então só
            // ocorre uma transição por aperto (sem repetição indesejada).
            AGUARDA_BOTAO: begin
                if (decrementar)
                    prox_estado = DECREMENTA;
                else if (incrementar)
                    prox_estado = INCREMENTA;
                else if (confirmar)
                    prox_estado = CONFIRMA;
            end

            // Decrementa o dígito apontado por idx, com rollover 0 -> 9.
            DECREMENTA: begin
                case (idx)
                    2'd0: prox_senha[0] = (senha[0] == 4'd0) ? 4'd9 : senha[0] - 4'd1;
                    2'd1: prox_senha[1] = (senha[1] == 4'd0) ? 4'd9 : senha[1] - 4'd1;
                    2'd2: prox_senha[2] = (senha[2] == 4'd0) ? 4'd9 : senha[2] - 4'd1;
                    2'd3: prox_senha[3] = (senha[3] == 4'd0) ? 4'd9 : senha[3] - 4'd1;
                endcase

                prox_estado = AGUARDA_BOTAO;
            end

            // Incrementa o dígito apontado por idx, com rollover 9 -> 0.
            INCREMENTA: begin
                case (idx)
                    2'd0: prox_senha[0] = (senha[0] == 4'd9) ? 4'd0 : senha[0] + 4'd1;
                    2'd1: prox_senha[1] = (senha[1] == 4'd9) ? 4'd0 : senha[1] + 4'd1;
                    2'd2: prox_senha[2] = (senha[2] == 4'd9) ? 4'd0 : senha[2] + 4'd1;
                    2'd3: prox_senha[3] = (senha[3] == 4'd9) ? 4'd0 : senha[3] + 4'd1;
                endcase

                prox_estado = AGUARDA_BOTAO;
            end

            // Confirma o dígito atual: avança o índice até o 4º (idx==3) e,
            // só então, segue para a verificação da senha.
            CONFIRMA: begin
                if (idx < 2'd3) begin
                    prox_idx = idx + 2'd1;
                    prox_estado = AGUARDA_BOTAO;
                end else begin
                    prox_estado = VERIFICAR_SENHA;
                end
            end

            // Compara a senha digitada com a senha fixa "1234".
            // Zera o timer para já entrar contando no estado seguinte.
            VERIFICAR_SENHA: begin
                prox_timer = 32'd0;

                if (senha[0] == 4'd1 &&
                    senha[1] == 4'd2 &&
                    senha[2] == 4'd3 &&
                    senha[3] == 4'd4)
                    prox_estado = COFRE_ABERTO;
                else
                    prox_estado = ACESSO_NEGADO;
            end

            // Mantém o cofre aberto por 5 s e depois volta ao início.
            COFRE_ABERTO: begin
                if (timer < TIME_5SEC - 1)
                    prox_timer = timer + 32'd1;
                else
                    prox_estado = INICIAL;
            end

            // Mantém o aviso de acesso negado por 3 s e depois volta ao início.
            ACESSO_NEGADO: begin
                if (timer < TIME_3SEC - 1)
                    prox_timer = timer + 32'd1;
                else
                    prox_estado = INICIAL;
            end

            // Segurança: qualquer estado inválido retorna ao início.
            default: begin
                prox_estado = INICIAL;
            end

        endcase
    end

    //=========================================================================
    // BLOCO 4: Saídas de LEDs (combinacional).
    // Verdes acesos no cofre aberto; vermelhos acesos no acesso negado.
    //=========================================================================
    always_comb begin
        LEDG = 9'b0;
        LEDR = 18'b0;

        if (estado == COFRE_ABERTO)
            LEDG = 9'b111111111;

        if (estado == ACESSO_NEGADO)
            LEDR = 18'b111111111111111111;
    end

    //=========================================================================
    // Decodificador de 7 segmentos (ativo em baixo: 0 = segmento aceso).
    // Recebe um dígito 0–9 e devolve o padrão dos 7 segmentos.
    //=========================================================================
    function automatic logic [6:0] sseg_decode(input logic [3:0] num);
    begin
        case (num)
            4'd0: sseg_decode = 7'b0000001;
            4'd1: sseg_decode = 7'b1001111;
            4'd2: sseg_decode = 7'b0010010;
            4'd3: sseg_decode = 7'b0000110;
            4'd4: sseg_decode = 7'b1001100;
            4'd5: sseg_decode = 7'b0100100;
            4'd6: sseg_decode = 7'b0100000;
            4'd7: sseg_decode = 7'b0001111;
            4'd8: sseg_decode = 7'b0000000;
            4'd9: sseg_decode = 7'b0000100;
            default: sseg_decode = 7'b1111111;  // Apagado p/ valores inválidos
        endcase
    end
	endfunction

    //-------------------------------------------------------------------------
    // Ligação dos displays:
    //   HEX3..HEX0 mostram os 4 dígitos da senha (esquerda -> direita)
    //   HEX4 mostra o índice do dígito atual de forma "humana" (1 a 4)
    //-------------------------------------------------------------------------
    assign HEX3 = sseg_decode(senha[0]);
    assign HEX2 = sseg_decode(senha[1]);
    assign HEX1 = sseg_decode(senha[2]);
    assign HEX0 = sseg_decode(senha[3]);
    assign HEX4 = sseg_decode(idx + 4'd1);

endmodule
