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
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "ipsxe_fft_def_v1_0.h"

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

void main() {   
    int fft_arch, log2_fft_len, output_order, scale_mode, round_mode, input_width, twiddle_width, fft_mode;
    // -----------------------------------------------   
    int blk_exp;
    
    struct ipsxe_fft_data *xn_comp; 
    struct ipsxe_fft_data *xk_comp;  

    double *re_exp;
    double *im_exp;
    
    int err = 0;
    
    int fft_size;
    int mem_size= 1024;
  
    int i, j;
    
    xn_comp = (struct ipsxe_fft_data*)malloc(mem_size * sizeof(struct ipsxe_fft_data));
    xk_comp = (struct ipsxe_fft_data*)malloc(mem_size * sizeof(struct ipsxe_fft_data));

    re_exp = (double*)malloc(mem_size * sizeof(double));
    im_exp = (double*)malloc(mem_size * sizeof(double));    
      
    // initialization
    for (i=0; i<2; i++) {
        // parameter definitions:
        if (i == 0) {                                     
            fft_arch = 0;
            log2_fft_len = 4;
            output_order = 1;
            scale_mode = 0;    
            round_mode = 1;
            input_width = 16;
            twiddle_width = 16;
            fft_mode = 1;
            xn_comp[0].creal  = 0x7FFF;
            xn_comp[1].creal  = 0x7EDF;
            xn_comp[2].creal  = 0x7B80;
            xn_comp[3].creal  = 0x75F3;
            xn_comp[4].creal  = 0x6E51;
            xn_comp[5].creal  = 0x64BC;
            xn_comp[6].creal  = 0x5960;
            xn_comp[7].creal  = 0x4C70;
            xn_comp[8].creal  = 0x3E26;
            xn_comp[9].creal  = 0x2EC3;
            xn_comp[10].creal = 0x1E8E;
            xn_comp[11].creal = 0x0DCE;
            xn_comp[12].creal = 0xFCCF;
            xn_comp[13].creal = 0xEBDF;
            xn_comp[14].creal = 0xDB4A;
            xn_comp[15].creal = 0xCB5B;
            
            xn_comp[0].cimag  = 0x0000;
            xn_comp[1].cimag  = 0x10F9;
            xn_comp[2].cimag  = 0x21A4;
            xn_comp[3].cimag  = 0x31B8;
            xn_comp[4].cimag  = 0x40EB;
            xn_comp[5].cimag  = 0x4EF9;
            xn_comp[6].cimag  = 0x5BA2;
            xn_comp[7].cimag  = 0x66AC;
            xn_comp[8].cimag  = 0x6FE6;
            xn_comp[9].cimag  = 0x7727;
            xn_comp[10].cimag = 0x7C4D;
            xn_comp[11].cimag = 0x7F41;
            xn_comp[12].cimag = 0x7FF6;
            xn_comp[13].cimag = 0x7E68;
            xn_comp[14].cimag = 0x7A9F;
            xn_comp[15].cimag = 0x74AC;
            // --------------------------------
            re_exp[0]  = 0x0391C6;
            re_exp[1]  = 0x1EC1CB;
            re_exp[2]  = 0x1FC138;
            re_exp[3]  = 0x000380;
            re_exp[4]  = 0x0023BD;
            re_exp[5]  = 0x00380A;
            re_exp[6]  = 0x0046F7;
            re_exp[7]  = 0x005333;
            re_exp[8]  = 0x005E34;
            re_exp[9]  = 0x0068EB;
            re_exp[10] = 0x007432;
            re_exp[11] = 0x00811E;
            re_exp[12] = 0x00915D;
            re_exp[13] = 0x00A878;
            re_exp[14] = 0x00CFB3;
            re_exp[15] = 0x012BBF;
                                     
            im_exp[0]  = 0x0586CB;
            im_exp[1]  = 0x1CDC99;
            im_exp[2]  = 0x1EA881;
            im_exp[3]  = 0x1F1FD5;
            im_exp[4]  = 0x1F59E4;
            im_exp[5]  = 0x1F7E70;
            im_exp[6]  = 0x1F994E;
            im_exp[7]  = 0x1FAF58;
            im_exp[8]  = 0x1FC327;
            im_exp[9]  = 0x1FD673;
            im_exp[10] = 0x1FEAC1;
            im_exp[11] = 0x000205;
            im_exp[12] = 0x001F46;
            im_exp[13] = 0x0048E4;
            im_exp[14] = 0x008F84;
            im_exp[15] = 0x01353E;            
        } 
        else {
            fft_arch = 1;
            log2_fft_len = 4;
            output_order = 0;
            scale_mode = 1;    
            round_mode = 0;
            input_width = 16;
            twiddle_width = 16;
            fft_mode = 0;

            xn_comp[0].creal  = 0x4572;
            xn_comp[1].creal  = 0xE7D1;
            xn_comp[2].creal  = 0xFB3B;
            xn_comp[3].creal  = 0x0044;
            xn_comp[4].creal  = 0x02B7;
            xn_comp[5].creal  = 0x0442;
            xn_comp[6].creal  = 0x0565;
            xn_comp[7].creal  = 0x0653;
            xn_comp[8].creal  = 0x0729;
            xn_comp[9].creal  = 0x07F9;
            xn_comp[10].creal = 0x08D5;
            xn_comp[11].creal = 0x09D0;
            xn_comp[12].creal = 0x0B0C;
            xn_comp[13].creal = 0x0CCE;
            xn_comp[14].creal = 0x0FC9;
            xn_comp[15].creal = 0x16C8;
            
            xn_comp[0].cimag  = 0x6B86;
            xn_comp[1].cimag  = 0xC2F1;
            xn_comp[2].cimag  = 0xE5E5;
            xn_comp[3].cimag  = 0xEEF6;
            xn_comp[4].cimag  = 0xF360;
            xn_comp[5].cimag  = 0xF627;
            xn_comp[6].cimag  = 0xF832;
            xn_comp[7].cimag  = 0xF9DF;
            xn_comp[8].cimag  = 0xFB60;
            xn_comp[9].cimag  = 0xFCD7;
            xn_comp[10].cimag = 0xFE63;
            xn_comp[11].cimag = 0x0027;
            xn_comp[12].cimag = 0x0261;
            xn_comp[13].cimag = 0x058A;
            xn_comp[14].cimag = 0x0AE8;
            xn_comp[15].cimag = 0x1781;
            // --------------------------------            
            re_exp[0]  = 0x1375;
            re_exp[1]  = 0x0973;
            re_exp[2]  = 0x10C4;
            re_exp[3]  = 0xFF84;
            re_exp[4]  = 0x12C5;
            re_exp[5]  = 0x04A5;
            re_exp[6]  = 0x0D96;
            re_exp[7]  = 0xFA6C;
            re_exp[8]  = 0x1348;
            re_exp[9]  = 0x071C;
            re_exp[10] = 0x0F4F;
            re_exp[11] = 0xFCF1;
            re_exp[12] = 0x11ED;
            re_exp[13] = 0x0219;
            re_exp[14] = 0x0B9E;
            re_exp[15] = 0xF800;
                                     
            im_exp[0]  = 0x0000;
            im_exp[1]  = 0x1102;
            im_exp[2]  = 0x09DE;
            im_exp[3]  = 0x1374;
            im_exp[4]  = 0x051D;
            im_exp[5]  = 0x12E5;
            im_exp[6]  = 0x0DED;
            im_exp[7]  = 0x12A5;
            im_exp[8]  = 0x0294;
            im_exp[9]  = 0x121E;
            im_exp[10] = 0x0C02;
            im_exp[11] = 0x1336;
            im_exp[12] = 0x078E;
            im_exp[13] = 0x1359;
            im_exp[14] = 0x0F9B;
            im_exp[15] = 0x11BC;                        
        }
               
        // run FFT/IFFT
        blk_exp = ipsxe_fft_wrapper_v1_0(xn_comp, xk_comp, fft_arch, log2_fft_len, output_order, scale_mode, round_mode, input_width, twiddle_width, fft_mode);   
    
        fft_size = pow(2, log2_fft_len);
        printf("----------------------------\n"); 
        printf("case%-d:\n", i+1);        
        printf("Transform Length: %-d\n", fft_size);
        printf("Input Data Width: %-d\n", input_width);
        printf("Twiddle Width: %-d\n", twiddle_width);
        
        if (fft_mode == 1)    
            printf("Type: FFT\n");
        else if (fft_mode == 0)
            printf("Type: IFFT\n");
        
        if (fft_arch == 0)    
            printf("Architecture: Pipeline\n");
        else if (fft_arch == 1)
            printf("Architecture: Radix-2 Burst\n");    
        
        if (output_order == 1)    
            printf("Output Order: Natural Order\n");
        else if (output_order == 0)
            printf("Output Order: Bit Reversed\n");  
            
        if (round_mode == 1)    
            printf("Round Mode: Convergent Rounding\n");
        else if (round_mode == 0)
            printf("Round Order: Truncation\n"); 
            
        if (scale_mode == 1)    
            printf("Scale Mode: Block Floating Point\n");
        else if (scale_mode == 0)
            printf("Scale Order: Unscaled\n");     
        
        printf("--------\n"); 
        printf("[Result]\n");                               
        printf("Block Exponential = %d\n", blk_exp);
        for (j=0; j<fft_size; j++) {
            if (xk_comp[j].creal != re_exp[j])
                err = 1;
            else if (xk_comp[j].cimag != im_exp[j])
                err = 1;
        }
        
        if (err == 1)
            printf("FFT Simulation is failed.\n");
        else
            printf("FFT Simulation is successful.\n");
    }
           
    free(re_exp);
    free(im_exp);
    free(xn_comp);
    free(xk_comp);    
}