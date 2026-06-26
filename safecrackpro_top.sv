module safecrackpro_top (
    input  logic clk,
    input  logic rstn,
    input  logic [2:0] btn,

    output logic [6:0] seg_pos1,
    output logic [6:0] seg_pos2,
    output logic [6:0] seg_pos3,
    output logic [6:0] seg_pos4,
    output logic [6:0] seg_cur_pos,

    output logic [17:0] led_red,
    output logic [8:0] led_green
);

    safecrackpro_fsm fsm_inst (
        .clk(clk),
        .KEY({btn, rstn}),
        .HEX0(seg_pos4),
        .HEX1(seg_pos3),
        .HEX2(seg_pos2),
        .HEX3(seg_pos1),
        .HEX4(seg_cur_pos),
        .LEDG(led_green),
        .LEDR(led_red)
    );

endmodule

