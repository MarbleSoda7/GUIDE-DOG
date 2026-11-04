# 重新同步 led_dbg_bit -> ov5640_hdmi_led 并推送
$root="D:\SDU\IC\HarnessProject\guide-dog"
$src="$root\ov5640_hdmi\led_dbg_bit"
$dst="$root\ov5640_hdmi_led"
robocopy "$src\ov5640_ps_hdmi.srcs" "$dst\ov5640_ps_hdmi.srcs" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$src\ip_repo" "$dst\ip_repo" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$src\led_src" "$dst\led_src" /MIR /NFL /NDL /NJH /NJS /NP /XF xgpio* Makefile CMakeLists.txt "Empty_applicationExample.cmake" app.yaml UserConfig.cmake README.txt | Out-Null
foreach($f in @("ov5640_ps_hdmi.xpr","add_led.tcl","add_led_build.tcl","flash_led.tcl","LED_CODE.md","_build_led_elf.ps1","_build_visible.bat","led_dbg_bitstream.bit")){ Copy-Item (Join-Path $src $f) $dst -Force }
Copy-Item "$src\build\led_node16.elf" "$dst\build\" -Force
Set-Location $root
git add ov5640_hdmi_led
git commit -m "update: sync ov5640_hdmi_led from working dir"
git push qian master
