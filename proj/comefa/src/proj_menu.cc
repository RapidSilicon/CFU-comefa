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
  for (unsigned long long a = 0; a < 1000; a += 1) {
      int expected = 0xffffffff;
      //The data width here is 40 bits. And we are streaming data in, so there
      //is no address to be sent. The address is incremented in the hardware itself.
      unsigned int a_lower = ~a;
      unsigned int a_higher = ~(a>>32); //Only 8 bits will be valid
      int cfu = cfu_op5(0, a_lower, a_higher);
      printf("Writing data %08x, %08x\n", a_higher, a_lower);
      printf("a: %08x b:%08x expected=%08x cfu= %08x\n", a_higher, a_lower, expected, cfu);
      //if (cfu != expected) {
      //  printf("\n***FAIL\n");
      //  return;
      //}
      count++;
  }
  printf("Performed %d comparisons", count);
}

//TODO: This will work only when swizzle_cram_to_dram is instantiated in the cfu
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
  //for (int a = 0x0; a < 0x64; a += 0x1) {
      //int expected = a;
      int cfu = cfu_op7(0, 0, 0); //Data written doesn't matter
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
        MENU_ITEM('0', "exercise cfu op0", do_exercise_cfu_op0),
        MENU_ITEM('1', "exercise cfu op1", do_exercise_cfu_op1),
        MENU_ITEM('2', "exercise cfu op2", do_exercise_cfu_op2),
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