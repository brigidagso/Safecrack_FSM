module safecrackpro_fsm #(
    parameter int CLK_FREQ = 50000000
)(
    input  logic clk,
    input  logic [3:0] KEY,

    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,

    output logic [8:0] LEDG,
    output logic [17:0] LEDR
);

    localparam int TIME_5SEC = 250000000;
    localparam int TIME_3SEC = 150000000;
    localparam int DEBOUNCE_MAX = 1000000;

    typedef enum logic [2:0] {
        INICIAL,
        AGUARDA_BOTAO,
        DECREMENTA,
        INCREMENTA,
        CONFIRMA,
        VERIFICAR_SENHA,
        COFRE_ABERTO,
        ACESSO_NEGADO
    } state_t;

    state_t estado, prox_estado;

    logic rstn;
    assign rstn = KEY[0];

    logic [3:0] senha [0:3];
    logic [3:0] prox_senha [0:3];

    logic [1:0] idx, prox_idx;
    logic [31:0] timer, prox_timer;

    logic key1_db, key2_db, key3_db;
    logic key1_old, key2_old, key3_old;
    logic [19:0] cnt1, cnt2, cnt3;

    logic confirmar;
    logic incrementar;
    logic decrementar;

    assign confirmar  = key1_old & ~key1_db;
    assign incrementar = key2_old & ~key2_db;
    assign decrementar = key3_old & ~key3_db;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
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
            key1_old <= key1_db;
            key2_old <= key2_db;
            key3_old <= key3_db;

            if (KEY[1] != key1_db) begin
                if (cnt1 >= DEBOUNCE_MAX) begin
                    key1_db <= KEY[1];
                    cnt1 <= 20'd0;
                end else begin
                    cnt1 <= cnt1 + 20'd1;
                end
            end else begin
                cnt1 <= 20'd0;
            end

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

    always_comb begin
        prox_estado = estado;
        prox_idx = idx;
        prox_timer = timer;

        prox_senha[0] = senha[0];
        prox_senha[1] = senha[1];
        prox_senha[2] = senha[2];
        prox_senha[3] = senha[3];

        case (estado)

            INICIAL: begin
                prox_idx = 2'd0;
                prox_timer = 32'd0;

                prox_senha[0] = 4'd0;
                prox_senha[1] = 4'd0;
                prox_senha[2] = 4'd0;
                prox_senha[3] = 4'd0;

                prox_estado = AGUARDA_BOTAO;
            end

            AGUARDA_BOTAO: begin
                if (decrementar)
                    prox_estado = DECREMENTA;
                else if (incrementar)
                    prox_estado = INCREMENTA;
                else if (confirmar)
                    prox_estado = CONFIRMA;
            end

            DECREMENTA: begin
                case (idx)
                    2'd0: prox_senha[0] = (senha[0] == 4'd0) ? 4'd9 : senha[0] - 4'd1;
                    2'd1: prox_senha[1] = (senha[1] == 4'd0) ? 4'd9 : senha[1] - 4'd1;
                    2'd2: prox_senha[2] = (senha[2] == 4'd0) ? 4'd9 : senha[2] - 4'd1;
                    2'd3: prox_senha[3] = (senha[3] == 4'd0) ? 4'd9 : senha[3] - 4'd1;
                endcase

                prox_estado = AGUARDA_BOTAO;
            end

            INCREMENTA: begin
                case (idx)
                    2'd0: prox_senha[0] = (senha[0] == 4'd9) ? 4'd0 : senha[0] + 4'd1;
                    2'd1: prox_senha[1] = (senha[1] == 4'd9) ? 4'd0 : senha[1] + 4'd1;
                    2'd2: prox_senha[2] = (senha[2] == 4'd9) ? 4'd0 : senha[2] + 4'd1;
                    2'd3: prox_senha[3] = (senha[3] == 4'd9) ? 4'd0 : senha[3] + 4'd1;
                endcase

                prox_estado = AGUARDA_BOTAO;
            end

            CONFIRMA: begin
                if (idx < 2'd3) begin
                    prox_idx = idx + 2'd1;
                    prox_estado = AGUARDA_BOTAO;
                end else begin
                    prox_estado = VERIFICAR_SENHA;
                end
            end

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

            COFRE_ABERTO: begin
                if (timer < TIME_5SEC - 1)
                    prox_timer = timer + 32'd1;
                else
                    prox_estado = INICIAL;
            end

            ACESSO_NEGADO: begin
                if (timer < TIME_3SEC - 1)
                    prox_timer = timer + 32'd1;
                else
                    prox_estado = INICIAL;
            end

            default: begin
                prox_estado = INICIAL;
            end

        endcase
    end

    always_comb begin
        LEDG = 9'b0;
        LEDR = 18'b0;

        if (estado == COFRE_ABERTO)
            LEDG = 9'b111111111;

        if (estado == ACESSO_NEGADO)
            LEDR = 18'b111111111111111111;
    end

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
            default: sseg_decode = 7'b1111111;
        endcase
    end
	endfunction

    assign HEX3 = sseg_decode(senha[0]);
    assign HEX2 = sseg_decode(senha[1]);
    assign HEX1 = sseg_decode(senha[2]);
    assign HEX0 = sseg_decode(senha[3]);
    assign HEX4 = sseg_decode(idx + 4'd1);

endmodule