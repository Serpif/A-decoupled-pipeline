module pipeline_alu #(
    parameter   DWIDTH = 4,
    parameter   RAM_DEPTH = 16
)
(
    input   clk,
    input   rstn,

    input  i_add_valid,
    output i_add_ready,
    input  [DWIDTH-1:0]    i_add_ins,
    input  [$clog2(RAM_DEPTH)-1:0] i_add_addr,
    input  [DWIDTH-1:0]    i_add_data,

    input  i_mul_valid,
    output   i_mul_ready,
    input  [DWIDTH-1:0]    i_mul_ins,
    input  [$clog2(RAM_DEPTH)-1:0] i_mul_addr,
    input  [DWIDTH-1:0]    i_mul_data,

// one cycle after i_add_valid && i_add_ready
    output  logic o_add_valid,
    input   o_add_ready,
    output  logic [$clog2(RAM_DEPTH)-1:0] o_add_addr,
    output  logic [DWIDTH-1:0]    o_add_data,

// two cycle after i_mul_valid && i_mul_ready
    output  logic o_mul_valid,
    input   o_mul_ready,
    output  logic [$clog2(RAM_DEPTH)-1:0] o_mul_addr,
    output  logic [DWIDTH-1:0]    o_mul_data

);

    logic   mul_valid_p1;
    logic   mul_ready_p1;
// ================== pipeline ctrl ================//

    always_ff @(posedge clk) begin
        if(~rstn)
            o_add_valid <= 1'b0;
        else if(i_add_ready)
            o_add_valid <= i_add_valid;
    end
    
    assign  i_add_ready = ~o_add_valid | o_add_ready;

    always_ff @(posedge clk) begin
        if(~rstn)
            mul_valid_p1 <= 1'b0;
        else if(i_mul_ready)
            mul_valid_p1 <= i_mul_valid;
    end

    always_ff @(posedge clk) begin
        if(~rstn)
            o_mul_valid <= 1'b0;
        else if(mul_ready_p1)
            o_mul_valid <= mul_valid_p1;
    end
    assign  mul_ready_p1 = ~o_mul_valid | o_mul_ready;
    assign  i_mul_ready = ~mul_valid_p1 | mul_ready_p1;


// ================ op add ======================//

    logic   [DWIDTH-1:0]    add_data_p1;
    logic   [DWIDTH-1:0]    add_ins_p1;
    always_ff @(posedge clk) begin
        if(~rstn) begin
            add_data_p1 <= 'd0;
            add_ins_p1 <= 'd0;
            o_add_addr <= 'd0;
        end
        else if(i_add_valid && i_add_ready) begin
            add_data_p1 <= i_add_data;
            add_ins_p1 <= i_add_ins;
            o_add_addr <= i_add_addr;
        end
    end

    assign  o_add_data = add_data_p1 + add_ins_p1;

// ================ op mult =====================//
// mult运算延迟2个时钟周期，目前实现的办法是将a拆分成上半和下半，
// 第一个时钟周期作两个部分的乘法
// 第二时钟周期作两个部分的加法
// 当然这个方法不是最优的，如果直接两数相乘，插入1拍寄存器，采用retime综合，时序最优
    logic  [$clog2(RAM_DEPTH)-1:0] mul_addr_p1;
    logic  [DWIDTH-1:0] mul_data_p1;
    logic  [DWIDTH-1:0] mul_ins_p1;

    always_ff @(posedge clk) begin
        if(~rstn) begin
            mul_addr_p1 <= 'd0;
            mul_data_p1 <= 'd0;
            mul_ins_p1 <= 'd0;
        end
        else if(i_mul_valid && i_mul_ready) begin
            mul_addr_p1 <= i_mul_addr;
            mul_data_p1 <= i_mul_data;
            mul_ins_p1 <= i_mul_ins;
        end
    end

    localparam  HALF_WIDTH0 = DWIDTH/2;
    localparam  HALF_WIDTH1 = DWIDTH - HALF_WIDTH0;
    logic   [DWIDTH+HALF_WIDTH0-1:0]     mult_tmp0;
    logic   [DWIDTH+HALF_WIDTH1-1:0]     mult_tmp1;
    
    always_ff @(posedge clk) begin
        if(~rstn) begin
            mult_tmp0 <= 'd0;
            mult_tmp1 <= 'd0;
            o_mul_addr <= 'd0;
        end
        else if(mul_valid_p1 && mul_ready_p1) begin
            mult_tmp0 <= mul_data_p1[HALF_WIDTH0-1:0] * mul_ins_p1;
            mult_tmp1 <= mul_data_p1[DWIDTH-1:HALF_WIDTH0] * mul_ins_p1;
            o_mul_addr <= mul_addr_p1;
        end
    end

    assign  o_mul_data = {mult_tmp1,{HALF_WIDTH0{1'b0}}} + {{HALF_WIDTH1{1'b0}},mult_tmp0};

endmodule