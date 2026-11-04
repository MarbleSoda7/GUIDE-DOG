
# XSCT script to generate FSBL from XSA

set xsa_path "D:/distortion_correction/vivado/guide_linux_base_100mhz/led_test_wrapper_100mhz.xsa"
set work_dir "D:/distortion_correction/vivado/guide_linux_base_100mhz/boot_repack"

# 设置工作目录
cd $work_dir

# 创建 Hardware Platform
puts "Creating hardware platform..."
setws .
platform create -name hw_platform -hw $xsa_path

# 创建 FSBL 应用
puts "Creating FSBL application..."
app create -name fsbl -platform hw_platform -domain standalone_ps7_cortexa9_0 -template "Zynq FSBL"

# 构建 FSBL
puts "Building FSBL..."
app build -name fsbl

puts "FSBL build complete"
puts "Output: $work_dir/fsbl/Debug/fsbl.elf"

exit
