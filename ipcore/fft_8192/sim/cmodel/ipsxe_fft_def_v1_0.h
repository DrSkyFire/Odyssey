//////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2022 PANGO MICROSYSTEMS, INC
// ALL RIGHTS REVERVED.
//
// THE SOURCE CODE CONTAINED HEREIN IS PROPRIETARY TO PANGO MICROSYSTEMS, INC.
// IT SHALL NOT BE REPRODUCED OR DISCLOSED IN WHOLE OR IN PART OR USED BY
// PARTIES WITHOUT WRITTEN AUTHORIZATION FROM THE OWNER.
//
//////////////////////////////////////////////////////////////////////////////

// FFT data format definition
struct ipsxe_fft_data {
  double creal;         // real
  double cimag;         // imaginary
};


// --------------------------------------------------------------------
// function: FFT wrapper
// parameters:
// fft_arch          0: pipeline; 1: radix-2 burst
// log2_fft_len      3~16
// output_order      1: natural; 0: bit reversed
// scale_mode        1: block floating point; 0: unscaled
// round_mode        1: convergent rounding; 0: truncation
// input_width       8~34
// twiddle_width     8~34

// configuration:
// fft_mode          1: fft; 0: ifft

// return: blk_exp
int ipsxe_fft_wrapper_v1_0(struct ipsxe_fft_data *xn, struct ipsxe_fft_data *result, int fft_arch, int log2_fft_len, int output_order, int scale_mode, int round_mode, int input_width, int twiddle_width, int fft_mode);