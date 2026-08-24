module tb_pipeline_demo (
);

    int global_seed = 121215145;

    parameter   DEPTH = 8;
    parameter   WIDTH = 16;

    logic   clk;
    logic   rstn;

    logic   i_valid;
    logic   i_ready;
    logic   opcode;
    logic   [$clog2(DEPTH)-1:0] addr;
    logic   [WIDTH-1:0] ins;

    logic   o_valid;
    logic   o_ready;
    logic   [$clog2(DEPTH)-1:0] o_addr;
    logic   [WIDTH-1:0] o_data;

    logic   [DEPTH-1:0][WIDTH-1:0]  test_mem={{WIDTH{1'b0}}};
    logic   op_tmp;
    int test_data_queue[0:DEPTH-1][$];   // pipeline的结果有延迟，用队列保序
    int test_ins_queue[0:DEPTH-1][$];   // pipeline的结果有延迟，用队列保序
    int test_opcode_queue[0:DEPTH-1][$];

    always 
    #5  clk = ~clk;

    initial begin
        // $urandom(global_seed);  // 设置全局随机数生成器种子
        clk = 0;
        rstn = 0;
        i_valid = 0;
        addr = 0;
        ins = 0;
        opcode = 0;
    //    o_ready = 0;
    #30 rstn = 1;
    end

    always_ff @(posedge clk) begin
        o_ready <= $urandom() % 8 < 3;    // 3/8 的概率发生反压
    end

    initial begin
    #50 @(posedge clk) #1;
        for(int i=0;i<DEPTH;i=i+1) begin
            write_in(i,0,i);
        end
    // $stop();
    #50;
        for(int i=0;i<100;i=i+1) begin
            op_tmp = $urandom % 2;
            if(op_tmp == 0) // 加法限制数<256
                write_in($urandom() % DEPTH,0,$urandom_range(255,0));
            else    // 1<= 乘法限制数 <=4
                write_in($urandom() % DEPTH,1,$urandom_range(4,1));
            repeat($urandom() %3) begin
                @(posedge clk) #1;
            end
        end
    $finish();
    end

    pipeline_demo #(DEPTH,WIDTH) u_pipe
    (
        .clk(clk),
        .rstn(rstn),

        .i_valid(i_valid),
        .i_ready(i_ready),
        .i_addr(addr),
        .i_opcode(opcode),
        .i_ins(ins),

        .o_valid(o_valid),
        .o_ready(o_ready),
        .o_addr(o_addr),
        .o_data(o_data)
    );

// 随机反压发生器

    task automatic write_in(
        input   [$clog2(DEPTH)-1:0]  wr_addr,
        input   wr_opcode,
        input   [WIDTH-1:0] wr_ins
    );
    int res;
    begin
        i_valid = 1;
        addr = wr_addr;
        ins = wr_ins;
        opcode = wr_opcode;
        res = wr_opcode ? test_mem[wr_addr] * wr_ins : test_mem[wr_addr] + wr_ins;
        test_mem[wr_addr] = res;
        test_ins_queue[wr_addr].push_back(wr_ins);
        test_data_queue[wr_addr].push_back(res);
        test_opcode_queue[wr_addr].push_back(wr_opcode);
        @(posedge clk);
        while (~i_ready) begin
            @(posedge clk);
        end
        #1;
        i_valid = 0;
        addr = 0;
        ins = 0;
    end
    endtask //automatic

    int qdata;
    int qopcode;
    int qins;
    int error_cnt;
    always_ff @(posedge  clk) begin
        if(~rstn)
            error_cnt = 0;
        else if(o_valid && o_ready) begin
            qdata = test_data_queue[o_addr].pop_front();
            qopcode = test_opcode_queue[o_addr].pop_front();
            qins = test_ins_queue[o_addr].pop_front();
            if(qdata != o_data) begin
                $error(" wrong number,in address %d opcode %d ins %d : expect %d but given %d",o_addr,qopcode,qins,qdata,o_data);
                error_cnt = error_cnt + 1'b1;
                if(error_cnt == 10) begin
                    $fatal(" error_cnt exceed to max th:10, stop simulation");
                end
            end
        end
    end

    int timeout_cnt;
    always_ff @(posedge clk) begin
        if(~rstn)
            timeout_cnt <= 'd0;
        else if((i_valid && i_ready) || (o_valid && o_ready)) begin
            timeout_cnt <= 'd0;
        end
        else begin
            timeout_cnt = timeout_cnt + 1;
            if(timeout_cnt == 1000 / 10 - 1) begin
                for(int i=0;i<DEPTH;i=i+1) begin
                    if(test_data_queue[i].size > 0) begin
                        $warning("There are still data in addr[%d]: ins is %d, result is %d; ",i,test_ins_queue[i],test_data_queue[i]);
                    end
                end
                $fatal("timeout error");
            end
        end
    end

endmodule