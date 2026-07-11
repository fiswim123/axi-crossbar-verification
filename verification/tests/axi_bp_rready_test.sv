//==========================================================================
// T072: R Channel Backpressure Test (UVM Sequence 版本)
//       通过配置 slave 延迟来模拟 R 通道反压
//==========================================================================
class axi_bp_rready_test extends axi_base_test;
    `uvm_component_utils(axi_bp_rready_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq  wr_seq;
        axi_rd_seq  rd_seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // Pre-write: 写入数据供后续读取
        for (int i = 0; i < 4; i++) begin
            wr_seq = axi_wr_seq::type_id::create($sformatf("prewr_%0d", i));
            wr_seq.s_addr = i * 4;
            wr_seq.s_data = 32'hA500_0000 + i;
            wr_seq.s_id   = 8'h10;
            wr_seq.start(env.sqr[0]);
        end

        // 配置 slave 响应延迟，制造 R 通道反压
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].delay_min = 3;
            env.slv_cfg[i].delay_max = 8;
        end

        // 读取数据，触发 R 通道反压
        for (int i = 0; i < 4; i++) begin
            rd_seq = axi_rd_seq::type_id::create($sformatf("bp_rd_%0d", i));
            rd_seq.s_addr = i * 4;
            rd_seq.s_id   = 8'h10;
            rd_seq.start(env.sqr[0]);
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
