// Slave-side specialization of the common AXI bus monitor.
class axi_slv_monitor extends axi_monitor;
    `uvm_component_utils(axi_slv_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
