/*
 * Copyright 2021 The CFU-Playground Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "proj_menu.h"

#include <stdio.h>

#include "cfu.h"
#include "menu.h"

namespace {

// Template Fn
void do_hello_world(void) { puts("Hello, World!!!\n"); }

// Test template instruction
void do_exercise_cfu_op0(void) {
  puts("\nExercise CFU Op0 aka ADD\n");
  int cfu;
  cfu = cfu_op0(1, 0, 0); //long reset//funct7 (first arg) is 1
  int count = 0;
  for (int a = 1; a <= 5; a += 1) {
    for (int b = 1; b <= 5; b += 1) {
      cfu = cfu_op0(0, a, b);
      printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, b, a + b, cfu);
      //if (cfu != a + b) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
    }
  }
  printf("Performed %d comparisons", count);
}

/*
// Test template instruction
void do_exercise_cfu_op1(void) {
  puts("\nExercise CFU Op1 aka SWAP\n");
  int count = 0;
  int b = 0;
  for (int a = 0x7; a < 0x77; a += 0x10) {
    int cfu = cfu_op1(0, a, b);
    int x = ((a & 0x000000ff) >> 0)  << 24; //extract leftmost 8 bits and move them to the rightmost 8 bits
    int y = ((a & 0x0000ff00) >> 8)  << 16; 
    int z = ((a & 0x00ff0000) >> 16) << 8; 
    int w = ((a & 0xff000000) >> 24) << 0; 
    int expected = x | y | z | w;
    printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, b, expected, cfu);
    if (cfu != expected) {
      printf("\n***FAIL\n");
      return;
    }
    count++;
  }
  printf("Performed %d comparisons", count);
}

// Test template instruction
void do_exercise_cfu_op2(void) {
  puts("\nExercise CFU Op2 aka Reverse\n");
  int count = 0;
  for (int a = 0x01010; a < 0x10101; a += 0x1000) {
      int cfu = cfu_op2(0, a, 0);
      int expected = 0;
      int isolater;
      int isolated;
      int shifted;
      for (int i=0; i<32; i++) {
        isolater = 1<<i;
        isolated = a & isolater;
        isolated = isolated >> i; //get to the lsb
        shifted = isolated << (31-i); //reverse
        expected = expected | shifted;
      }
      printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      if (cfu != expected) {
        printf("\n***FAIL\n");
        return;
      }
      count++;
  }
  printf("Performed %d comparisons", count);
}
*/

// Test template instruction
void do_exercise_cfu_op3(void) {
  puts("\nExercise CFU Op3 aka Write to INST_RAM\n");
  int count = 0;
  for (int a = 0x0; a < 0x64; a += 0x1) {
      int expected = 0xffffffff;
      //Instructions are 32 bits.
      //We write 1 instruction in 1 cycle to 1 address.
      //One argument of the instruction is the data (i.e the macro instruction to be stored in the RAM)
      //Second argument of the instruction is the address to which it should be written.
      int cfu = cfu_op3(0, a, a); 
      printf("Writing data %08x to address %08x\n", a, a);
      printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, a, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
  }
  printf("Performed %d comparisons", count);
}

// Test template instruction
void do_exercise_cfu_op4(void) {
  puts("\nExercise CFU Op4 aka Read from INST_RAM\n");
  int count = 0;
  for (int a = 0x0; a < 0x64; a += 0x1) {
      int expected = a;
      int cfu = cfu_op4(0, a, 0);
      printf("Read data %08x from address %08x\n", cfu, a);
      printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
  }
  printf("Performed %d comparisons", count);
}

// Test template instruction
void do_exercise_cfu_op5(void) {
  puts("\nExercise CFU Op5 aka Write to Comefa RAM\n");
  int count = 0;
  //Taking a as long int (64 bits).
  //But only 40 bits will be valid.

  //Let's say we want to multiply two arrays. Each array has 160x4 elements.
  //Each element is 8 bits. 
  //Array 1 is called "A" and Array 2 is called "B".
  //We can send 40 bits at a time. So, we can actually A and B together.

  //40 bits are real data. We have 64 bits. So, we are left with 24 bits.
  //Let's send the address of the row we need to write to.
  //Row addresses are 7 bits.

  //Say, we want the data to be located at row address 4.
  unsigned int row_addr = 3; //we increment in the loop
  unsigned int ram_addr = row_addr<<2;     //need to shift left by 2 to get from row address
                                           //to normal addr coz the column muxing factor is 4.

  unsigned char A[160*4];
  unsigned char B[160*4];

  for (unsigned int i=0; i<160; i++) {
    //Keeping all 4 parts of the arrays the same for easy debug.
    //This ensures that the contents of each RAM are the same.
    A[i+0*160] = i;
    B[i+0*160] = i+10;
    A[i+1*160] = i;
    B[i+1*160] = i+10;
    A[i+2*160] = i;
    B[i+2*160] = i+10;
    A[i+3*160] = i;
    B[i+3*160] = i+10;
  }

  int cfu = 0;
  do {
    cfu = cfu_op5(2, 0, 0); //set funct7 to 2 to indicate we are checking for readyness
  } while (cfu==0); //cfu will be 1 when ready
  printf("CFU is ready to accept data");

  for (unsigned int i = 0; i < 160*4; i += 1) {
      int expected = 0xffffffff;
      
      //We send 8 bits of an element of A and 8 bits of an element of B in the lower part of the data
      //(actually the lower 40 bits).
      //When the data gets transposed, the A bits and B bits will be in consecutive rows.
      unsigned int lower = (B[i]<<8) |  A[i];


      if ((i>0) && (i%160==0)) {
        ram_addr = ram_addr + (1<<9); //the 1<<9 is to change the higher order bits
                                      //that decide which RAM the data goes to. 
                                      //after every 160 columns, we want to move to
                                      //the next ram.
      }

      //We send the row address in the upper part of the data (bits 47:41).
      //need to shift left by 8 to get to bit 
      //position 40 in the concatenated {higher,lower} value.
      unsigned int higher = ram_addr<<8; 

      if ((i==159) || (i==319) || (i==479) || (i==639)) {
        cfu = cfu_op5(1, lower, higher); //set funct7 to 1 to indicate this is the last
        printf("Writing data %08x at ram address %08x (higher =%08x)\n", lower, ram_addr, higher);
        printf("i: %08d A: %08x B:%08x expected=%08x cfu= %08x\n", i, A[i], B[i], expected, cfu);

        //after that wait for readyness
        do {
          cfu = cfu_op5(2, 0, 0); //set funct7 to 2 to indicate we are checking for readyness
        } while (cfu==0); //cfu will be 1 when ready
        printf("Swizzle logic has been flushed\n");
      }
      else {
        cfu = cfu_op5(0, lower, higher);
        printf("Writing data %08x at ram address %08x (higher =%08x)\n", lower, ram_addr, higher);
        printf("i: %08d A: %08x B:%08x expected=%08x cfu= %08x\n", i, A[i], B[i], expected, cfu);
      }
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
  }
  printf("Sent %d values", count);


}

// Test template instruction
void do_exercise_cfu_op6(void) {
  puts("\nExercise CFU Op6 aka Read from Comefa RAM\n");
  int count = 0;
  int num_elements_to_read = 100;
  int starting_addr = 10;
  for (int a = 0x0; a < 200; a += 0x1) {
      //int expected = a;
      int cfu = cfu_op6(0, starting_addr, num_elements_to_read);
      printf("Read data %08x\n", cfu);
      //printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
  }
  printf("Performed %d comparisons", count);
}

//TODO: Change this so that one value starts and the return value is used to see if the work is done
void do_exercise_cfu_op7_start(void) {
  puts("\nExercise CFU Op7_start aka Start Execution\n");
  //int count = 0;
  int cfu;
  //for (int a = 0x0; a < 0x64; a += 0x1) {
      //int expected = a;
      int inst_start_addr = 2;
      int inst_end_addr = 3;
      cfu = cfu_op7(2, inst_start_addr, inst_end_addr);  //configure start and end addresses

      cfu = cfu_op7(0, 0, 0); //actually start the computation
      printf("Got result %08x after starting execution\n", cfu);
      //printf("Read data %08x from address %08x\n", cfu, a);
      //printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      //count++;
  //}
  //printf("Performed %d comparisons", count);
}

//TODO: Change this so that one value starts and the return value is used to see if the work is done
void do_exercise_cfu_op7_check(void) {
  puts("\nExercise CFU Op7_check aka Check Execution\n");
  //int count = 0;
  int cfu=0;
  //for (int a = 0x0; a < 0x64; a += 0x1) {
      //int expected = a;
      while (cfu!=1) {
        cfu = cfu_op7(1, 0, 0); //Data written doesn't matter
        printf("Got result %08x after starting execution\n", cfu);
      }
      printf("Execution finished\n");
      //printf("Read data %08x from address %08x\n", cfu, a);
      //printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      //count++;
  //}
  //printf("Performed %d comparisons", count);
}

void do_exercise_cfu_op7_write_rf(void) {
  puts("\nExercise CFU Op7_write_rf aka Write RF\n");
  //int count = 0;
  //for (int a = 0x0; a < 0x64; a += 0x1) {
      int expected = 0xffffffff;
      int cfu;
      cfu = cfu_op7(2, 12, 0); 
      if (cfu != expected) {
        printf("\n***FAIL\n");
      }
      cfu = cfu_op7(2, 13, 1); 
      if (cfu != expected) {
        printf("\n***FAIL\n");
      }
      cfu = cfu_op7(2, 14, 2); 
      if (cfu != expected) {
        printf("\n***FAIL\n");
      }
      cfu = cfu_op7(2, 15, 3); 
      if (cfu != expected) {
        printf("\n***FAIL\n");
      }
      printf("Got result %08x after starting execution\n", cfu);
      //printf("Read data %08x from address %08x\n", cfu, a);
      //printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a, 0, expected, cfu);
      //count++;
  //}
  //printf("Performed %d comparisons", count);
}

struct Menu MENU = {
    "Project Menu",
    "project",
    {
        MENU_ITEM('0', "exercise cfu op0 - reset and test", do_exercise_cfu_op0),
        MENU_ITEM('3', "exercise cfu op3 - write iram", do_exercise_cfu_op3),
        MENU_ITEM('4', "exercise cfu op4 - read iram", do_exercise_cfu_op4),
        MENU_ITEM('5', "exercise cfu op5 - write comefa", do_exercise_cfu_op5),
        MENU_ITEM('6', "exercise cfu op6 - read comefa", do_exercise_cfu_op6),
        MENU_ITEM('7', "exercise cfu op7 - start execution", do_exercise_cfu_op7_start),
        MENU_ITEM('8', "exercise cfu op7 - check status of execution", do_exercise_cfu_op7_check),
        MENU_ITEM('9', "exercise cfu op7 - Set registers", do_exercise_cfu_op7_write_rf),
        MENU_ITEM('h', "say Hello", do_hello_world),
        MENU_END,
    },
};
};  // anonymous namespace

extern "C" void do_proj_menu() { menu_run(&MENU); }