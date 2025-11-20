//=============================================================================
// Copyright 2025 DrSkyFire
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//     http://www.apache.org/licenses/LICENSE-2.0
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//=============================================================================
// 文件名: hdmi_tx.v
// 描述: HDMI发送模块 - MS7210驱动
// 功能: 
//   1. MS7210初始化配置
//   2. RGB数据输出
//=============================================================================

module hdmi_tx (
    input  wire         clk_pixel,          // 像素时钟 148.5MHz
    input  wire         rst_n,
    
    // 视频输入
    input  wire [23:0]  rgb,                // RGB数据
    input  wire         de,                 // 数据使能
    input  wire         hs,                 // 行同步
    input  wire         vs,                 // 场同步
    
    // HDMI物理输出（连接到MS7210）
    output wire         tmds_clk_p         // 像素时钟输出
);

assign tmds_clk_p = clk_pixel;

endmodule