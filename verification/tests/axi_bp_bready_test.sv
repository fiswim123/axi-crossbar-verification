//==========================================================================
// T071: B Channel Backpressure Test (UVM Sequence 版本)
//       通过配置 slave 延迟来模拟 B 通道反压
//==========================================================================
class axi_bp_bready_test extends axi_base_test;
    `uvm_component_utils(axi_bp_bready_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_burst_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // 配置 slave 响应延迟，制造 B 通道反压
        for (int i = 0; i < 4; i++) begin
            env.slv_cfg[i].delay_min = 3;
            env.slv_cfg[i].delay_max = 8;
        end

        // 发送 burst 写事务
        for (int i = 0; i < 4; i++) begin
            seq = axi_burst_wr_seq::type_id::create($sformatf("bp_%0d", i));
            seq.s_addr = 16'h0000;
            seq.s_id   = 8'h10;
            seq.s_len  = 3;  // 4-beat burst
            seq.start(env.sqr[0]);
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
