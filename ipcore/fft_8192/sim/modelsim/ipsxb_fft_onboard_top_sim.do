file delete -force work
file delete -force vsim_ipsxb_fft_onboard_top.log
vlib  work
vmap  work work
vlog -incr -sv \
D:/pango/PDS_2022.2-SP6.4/ip/system_ip/ipsxb_fft/ipsxb_fft_eval/ipsxb_fft/../../../../../arch/vendor/pango/verilog/simulation/GTP_APM_E1.v \
D:/pango/PDS_2022.2-SP6.4/ip/system_ip/ipsxb_fft/ipsxb_fft_eval/ipsxb_fft/../../../../../arch/vendor/pango/verilog/simulation/GTP_DRM18K_E1.v \
D:/pango/PDS_2022.2-SP6.4/ip/system_ip/ipsxb_fft/ipsxb_fft_eval/ipsxb_fft/../../../../../arch/vendor/pango/verilog/simulation/GTP_DRM36K_E1.v \
D:/pango/PDS_2022.2-SP6.4/ip/system_ip/ipsxb_fft/ipsxb_fft_eval/ipsxb_fft/../../../../../arch/vendor/pango/verilog/simulation/GTP_GRS.v \
D:/pango/PDS_2022.2-SP6.4/ip/system_ip/ipsxb_fft/ipsxb_fft_eval/ipsxb_fft/../../../../../arch/vendor/pango/verilog/simulation/GTP_DRM9K.v \
-f ./ipsxb_fft_onboard_top_filelist.f -l vlog.log
vsim {-voptargs=+acc} work.ipsxb_fft_onboard_top_tb -l vsim.log
do ipsxb_fft_onboard_top_wave.do
run -all
