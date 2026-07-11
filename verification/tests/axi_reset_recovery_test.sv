//==========================================================================
// T082: Reset Recovery Test (UVM Sequence 版本)
//       多次 reset 循环，验证 DUT 每次都能恢复正常
//==========================================================================
class axi_reset_recovery_test extends axi_base_test;
    `uvm_component_utils(axi_reset_recovery_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_wr_seq seq;
        phase.raise_objection(this);
        @(posedge env.mst_drv[0].vif.aresetn);
        repeat(5) @(posedge env.mst_drv[0].vif.aclk);

        // T082: 3 次 reset 循环
        for (int cycle = 0; cycle < 3; cycle++) begin
            // 正常操作: 写 4 个事务
            for (int i = 0; i < 4; i++) begin
                seq = axi_wr_seq::type_id::create(
                    $sformatf("c%0d_w%0d", cycle, i));
                seq.s_addr = i * 4;
                seq.s_data = 32'hA500_0000 + cycle * 4 + i;
                seq.s_id   = 8'h10;
                seq.start(env.sqr[0]);
            end

            #50;

            // 触发 reset
            env.mst_drv[0].vif.aresetn <= 0;
            repeat(10) @(posedge env.mst_drv[0].vif.aclk);
            env.mst_drv[0].vif.aresetn <= 1;
            repeat(20) @(posedge env.mst_drv[0].vif.aclk);
        end

        // 最终验证: reset 恢复后应能正常工作
        for (int i = 0; i < 4; i++) begin
            seq = axi_wr_seq::type_id::create($sformatf("final_%0d", i));
            seq.s_addr = i * 4;
            seq.s_data = 32'hA500_0010 + i;
            seq.s_id   = 8'h10;
            seq.start(env.sqr[0]);
        end

        #200;
        phase.drop_objection(this);
    endtask
endclass
