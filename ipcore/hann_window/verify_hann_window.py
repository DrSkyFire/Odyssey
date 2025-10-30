#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Hann窗系数验证脚本
读取生成的HEX文件并绘制窗函数曲线
"""

import numpy as np
import matplotlib.pyplot as plt

# 读取HEX文件
window_q15 = []
with open('hann_window_8192.hex', 'r') as f:
    for line in f:
        val = int(line.strip(), 16)
        window_q15.append(val)

# 转换回浮点数
window = np.array(window_q15, dtype=np.float64) / 32767.0

# 绘图
plt.figure(figsize=(12, 6))
plt.subplot(2, 1, 1)
plt.plot(window)
plt.title('Hann Window - 8192 points')
plt.xlabel('Sample')
plt.ylabel('Amplitude')
plt.grid(True)

# FFT分析（显示频域特性）
plt.subplot(2, 1, 2)
window_fft = np.fft.fft(window, 16384)
window_fft_db = 20 * np.log10(np.abs(window_fft[:8192]) + 1e-10)
plt.plot(window_fft_db)
plt.title('Hann Window - Frequency Response')
plt.xlabel('Frequency Bin')
plt.ylabel('Magnitude (dB)')
plt.grid(True)
plt.ylim([-100, 20])

plt.tight_layout()
plt.savefig('hann_window_plot.png', dpi=150)
print('Verification plot saved: hann_window_plot.png')
plt.show()
