.syntax unified
.global main
.include "libcomp2300/macros.S"


.type main, %function
main:
  @setup
  bl init
  bl BSP_AUDIO_Buffer

  ldr r0, =state

  @ enable SYSCFG clock
  RCC_APB2ENR_set 0

  @ turn on the clock for GPIO ports B, D and E 
  GPIOx_clock_enable B
  GPIOx_clock_enable E
  GPIOx_clock_enable D

  GPIO_configure_output_pin E, 14 @note on/off sender
  GPIO_configure_output_pin E, 15 @pitch change sender  

  GPIO_configure_input_pin_it D, 0 @note on/off reciever 
  EXTI_set_rising_edge_trigger 0
  EXTI_set_falling_edge_trigger 0
  NVIC_set ISER 6

  GPIO_configure_input_pin_it B, 3 @pitch change reciever 
  EXTI_set_rising_edge_trigger 3
  NVIC_set ISER 9

  @timer setup - interval of 0.25 seconds
  ldr r0, =10000
  ldr r1, =2000
  bl tim7_init @timer setup

  @wave setup
  mov r0, 22000
  ldr r1, =0x7FFF
  bl wave_change

  GPIOx_ODR_set E, 14 @set E14  

  b loop
.size main, .-main

@note on/off handler - PD0 - PE14
.global EXTI0_IRQHandler
.type EXTI0_IRQHandler, %function
EXTI0_IRQHandler:
  push {r0-r12, lr}

  EXTI_PR_clear_pending 0

  @update the state - 0 to play, 1 to not play
  ldr r0, =state
  ldr r1, [r0]
  cmp r1, 0
  ITE EQ
  moveq r1, 1
  movne r1, 0

  str r1, [r0]

  pop {r0-r12, lr}
  bx lr 


@pitch change handler - PB3 - PE15
.global EXTI3_IRQHandler
.type EXTI3_IRQHandler, %function
EXTI3_IRQHandler:
  push {r0-r12, lr}

  EXTI_PR_clear_pending 3
  
  @clear sender (PE15)
  GPIOx_ODR_clear E, 15

  @add to prev_note, check if it's gone past the array end and store
  ldr r0, =note_counter_reciever
  ldr r1, [r0]
  adds r1, 1

  @check if silence 
  cmp r1, 8
  IT EQ
  moveq r1, 0
  str r1, [r0]

  @get note value
  mov r2, 4
  mul r1, r2
  ldr r0, =pitch_table
  ldr r0, [r0, r1]
  @update wave
  ldr r1, =0x7FFF
  bl wave_change

  bl sync

  pop {r0-r12, lr}
  bx lr 

.global loop
.type loop, %function
loop:
  @check note 
  ldr r0, =state
  ldr r1, [r0]
  cmp r1, 1
  beq loop_play @if current state = play

  ldr r4, =sequence_counter
  ldr r3, [r4]
  mov r4, 4
  mul r3, r4 @note's location in sequence

  ldr r4, =sequence
  ldr r3, [r4, r3] @target note

  ldr r5, =note_counter_sender
  ldr r6, [r5] @current note

  @if current note != target note, update the note
  cmp r3, r6
  bne update_loop 

  b loop

update_loop:
  @compare prev note and target note
  @if equal don't need to do anything, so branch to loop
  push {r0 - r3} 
  GPIOx_ODR_toggle E, 15 @set E15 to send update frequency message 
  pop {r0 - r3} 

  ldr r4, =sequence_counter
  ldr r3, [r4]
  mov r4, 4
  mul r3, r4 @note's location in sequence

  ldr r4, =sequence
  ldr r3, [r4, r3] @target note

  ldr r5, =note_counter_sender
  ldr r6, [r5] @current note
  add r6, 1

  cmp r6, 8
  IT EQ
  moveq r6, 0

  str r6, [r5]

  cmp r3, r6
  bne update_loop @if current != target note stay in update loop

  b loop

@plays the current note
loop_play:
  bl wave_play_next_sample
  b loop

@timer helpers:
.global silence
.type silence, %function
silence:
  push {r0-r5, lr}
  GPIOx_ODR_clear E, 14 @clear E14  
  pop {r0-r5, lr}
  bx lr

.global not_silence
.type not_silence, %function
not_silence:
  push {r0-r5, lr}
  GPIOx_ODR_set E, 14 @set E14  
  pop {r0-r5, lr}
  bx lr

.data
.align 2 @ align memory addresses to a word boundry (leave here)
@ \/ memory entries go below \/

@song array - stored in frequency, (time * 48000) pairs 
@8 = silence, otherwise corresponds to the pitch table value
.global sequence
sequence:
  .word 0, 8, 2, 8, 1, 8, 3, 8, 2, 8, 4, 8, 3, 8, 5, 8, 4, 8, 6, 8, 5, 8, 7, 8, 6, 8, 5, 8, 4, 8, 3, 8, 2, 8, 1, 8, 0, 8, 9

.global pitch_table
pitch_table:
  .word 22000
  .word 24694
  .word 26163
  .word 29366
  .word 32963
  .word 36999
  .word 39200
  .word 44000

.global state
state:
  .word 0 @0 - silence, 1 - playing 

.global sequence_counter
sequence_counter:
  .word 0

note_counter_reciever:
  .word 0 @target note index (reciever's) - doesn't include silence

note_counter_sender: 
  .word 0 @target note index (sender's) - doesn't include silence