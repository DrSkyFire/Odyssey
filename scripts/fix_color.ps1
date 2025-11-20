$file = "source\source\hdmi_display_ctrl.v"
#
# Copyright 2025 DrSkyFire
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
$content = Get-Content $file -Raw

# 替换颜色判断逻辑为表格式布局
$content = $content -replace 'if \(pixel_y_d4 < PARAM_Y_START \+ 20\)\s+\/\/', 'if (pixel_y_d4 < TABLE_Y_CH1)                   //'
$content = $content -replace 'else if \(pixel_y_d4 < PARAM_Y_START \+ 40\)\s+\/\/', 'else if (pixel_y_d4 < TABLE_Y_CH2)              //'
$content = $content -replace 'else if \(pixel_y_d4 < PARAM_Y_START \+ 60\)\s+\/\/', 'else if (pixel_y_d4 < TABLE_Y_PHASE)            //'
$content = $content -replace 'else if \(pixel_y_d4 < PARAM_Y_START \+ 80\)\s+\/\/', '// 删除这行'
$content = $content -replace 'else if \(pixel_y_d4 < PARAM_Y_START \+ 100\)\s+\/\/', '// 删除这行'

# 替换颜色值
$content = $content -replace "char_color = 24'h00FFFF;  \/\/ 青色 - 频率", "char_color = 24'hFFFFFF;  // 白色 - 表头"
$content = $content -replace "char_color = 24'hFFFF00;  \/\/ 黄色 - 幅度", "char_color = 24'h00FF00;  // 绿色 - CH1"
$content = $content -replace "char_color = 24'h00FF00;  \/\/ 绿色 - 占空比", "char_color = 24'hFF0000;  // 红色 - CH2"

$content | Set-Content $file -NoNewline
Write-Host "修复完成！"
