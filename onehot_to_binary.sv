module onehot_to_binary #(
    parameter   WIDTH = 10
) (
    input   logic [WIDTH-1:0] onehot,
    output  logic [$clog2(WIDTH)-1:0] binary
);

    integer i;
    always_comb begin
        binary = {$clog2(WIDTH){1'b0}};
        for(i=0;i<WIDTH;i=i+1) begin
            if(onehot[i] == 1'b1) 
                binary = i;
        end
    end
    
endmodule