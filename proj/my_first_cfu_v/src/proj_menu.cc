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
  cfu = cfu_op0(1, 0, 0); //dummy //funct7 (first arg) is 1
  int count = 0;
  for (int a = 0; a < 5; a += 1) {
    for (int b = 0; b < 5; b += 1) {
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
  puts("\nExercise CFU Op3 aka Store\n");
  int count = 0;
  for (int a = 0x0; a < 0x64; a += 0x1) {
      int expected = 0xffffffff;
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
  puts("\nExercise CFU Op4 aka Load\n");
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

struct Menu MENU = {
    "Project Menu",
    "project",
    {
        MENU_ITEM('0', "exercise cfu op0", do_exercise_cfu_op0),
        MENU_ITEM('1', "exercise cfu op1", do_exercise_cfu_op1),
        MENU_ITEM('2', "exercise cfu op2", do_exercise_cfu_op2),
        MENU_ITEM('3', "exercise cfu op3", do_exercise_cfu_op3),
        MENU_ITEM('4', "exercise cfu op4", do_exercise_cfu_op4),
        MENU_ITEM('h', "say Hello", do_hello_world),
        MENU_END,
    },
};
};  // anonymous namespace

extern "C" void do_proj_menu() { menu_run(&MENU); }