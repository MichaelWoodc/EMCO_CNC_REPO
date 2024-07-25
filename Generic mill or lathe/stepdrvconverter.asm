;******************************************************************************
;                                                                             *
;    Filename:      stepdrvconverter.asm                                      *
;    Date:          14/03/2014                                                *
;    File Version:  V0.1                                                      *
;                                                                             *
;    Author:        Frédéric Ruiter                                           *
;    MAIL :         darc2me@wanadoo.fr                                        *
;******************************************************************************
;    Files required: P12F683.INC                                              *
;******************************************************************************
;                                                                             *
;    Notes: halfstep/fulstepmode on line 108,112,137,222                      *
;           KEEP  in mind that with the ICD2 could programmable 1 time        *
;          the driver will set the motor in shopper mode after 1 minute       *
;          without steps to avoid overheat at 600Hz                           *
;          it come out of this mode on the next step                          *
;          tested only on comstep board at 1kHz steps                         *
;          i don't know how fast it could be                                  *
;                                                                             *
;                                                                             *
;                                                                             *
;******************************************************************************
;header pickit2 ->pic16F863
;1 Vpp ->4
;2 Vdd ->1
;3 Vss ->8
;4 PGD ->7
;5 PGC ->6
;6 aux ...
;                        _________
;VDD                     | 1    8| Vss
;GP5/T1CLK/OSC1/CLKIN    | 2    7| GP0/AN0/CIN+/ICSPDAT/ULPWU
;GP4/AN2/T1G/OSC2/CLKOUT | 3    6| GP1/AN1/CIN-/Vref/ICSPCLK
;GP3/MCLR                | 4    5| GP2/AN2/T0CKI/INT/COUT/
;                        ---------
;pin 2 =phase A
;pin 3 =phase B
;pin 6 =phase C
;pin 7 =phase D
;pin 5 =phase STEP
;pin 4 =phase DIR

;------------------------------------------------------------------------------
; PROCESSOR DECLARATION
;------------------------------------------------------------------------------

     LIST      P=12F683              ; list directive to define processor
     #INCLUDE <C:\Users\fredo\projects\stepper\P12F683.INC>          ; processor specific variable definitions

;------------------------------------------------------------------------------
;
; CONFIGURATION WORD SETUP
;
; to be reprogrammable change MCLRE_OFF to MCLRE_ON
; the device will have only one direction
;------------------------------------------------------------------------------

    __CONFIG   _FCMEN_ON & _IESO_OFF & _CP_OFF & _CPD_OFF & _BOD_OFF & _MCLRE_OFF & _WDT_OFF & _PWRTE_OFF & _INTRC_OSC_NOCLKOUT 

;------------------------------------------------------------------------------
; VARIABLE DEFINITIONS
;------------------------------------------------------------------------------

; example of using Shared Uninitialized Data Section
INT_VAR     UDATA_SHR      
W_TEMP      RES     1             ; variable used for context saving 
STATUS_TEMP RES     1             ; variable used for context saving
INT_VAR2		UDATA_SHR	0x71
; CBLOCK  0x71
stepcount           RES	    1
steps               RES	    1
oldsteps            RES	    1
tmrbyte1            RES	    1
tmrbyte2            RES	    1
tmrbyte3            RES	    1
tmrstatus           RES	    1
pwmcounter          RES	    1

;------------------------------------------------------------------------------
; EEPROM INITIALIZATION
;
; The 12F683 has 256 bytes of non-volatile EEPROM, starting at address 0x2100
; 
;------------------------------------------------------------------------------

DATAEE    CODE  0x2100
    DE    "DARC"          ; Place 'D' 'A' 'R' 'C' at address 0,1,2,3

;------------------------------------------------------------------------------
; RESET VECTOR
;------------------------------------------------------------------------------

RESET_VECTOR  CODE    0x0000  ; processor reset vector
        GOTO    START         ; go to beginning of program

;------------------------------------------------------------------------------
; INTERRUPT SERVICE ROUTINE
;------------------------------------------------------------------------------

INT_VECTOR    CODE    0x0004  ; interrupt vector location
        MOVWF   W_TEMP        ; save off current W register contents
        MOVF    STATUS,w      ; move status register into W register
        MOVWF   STATUS_TEMP   ; save off contents of STATUS register
 BANKSEL INTCON
 BCF INTCON,GIE
 MOVF    GPIO
 BTFSC INTCON,GPIF
 BCF  INTCON,GPIF
 BTFSS INTCON,T0IF
 BCF  INTCON,T0IF
 BTFSS INTCON,INTF
 goto end_int

 BTFSS GPIO,GP2 ;check GPIO,GP2 step
 goto end_int
 BTFSS GPIO,GP3 ;check GPIO,GP3 dir
 goto ccw

cw
 incf stepcount,W
; ANDLW 0x03 ;fullstep
 ANDLW 0x07 ;halfstep
 MOVWF stepcount
; CALL Table_fullstep
 CALL Table_halfstep ;halfstep
 ;-------bridge switch delay---
 MOVWF steps
 XORWF oldsteps,W
 XORLW 0xFF
 ANDWF steps,W
 MOVWF GPIO
 NOP
 MOVF steps,W
;-------bridge switch delay---
 MOVWF GPIO
 MOVWF oldsteps
;-------clear pwm counter -----
 CLRF tmrbyte1
 CLRF tmrbyte2
 CLRF tmrbyte3
 BCF tmrstatus,0x00 ; clr pwm mode

 goto end_int

ccw
 decf stepcount,W
; ANDLW 0x03 ;fullstep
 ANDLW 0x07 ;halfstep
 MOVWF stepcount
; CALL Table_fullstep ;halfstep
 CALL Table_halfstep
;-------bridge switch delay---
 MOVWF steps
 XORWF oldsteps,W
 XORLW 0xFF
 ANDWF steps,W
 MOVWF GPIO
 NOP
 MOVF steps,W
;-------bridge switch delay---
 MOVWF GPIO
 MOVWF oldsteps
;-------clear pwm counter -----
 CLRF tmrbyte1
 CLRF tmrbyte2
 CLRF tmrbyte3
 BCF tmrstatus,0x00 ; clr pwm mode

end_int

 BANKSEL INTCON

       BCF INTCON,INTF
; isr code can go here or be located as a call subroutine elsewhere

        MOVF    STATUS_TEMP,w ; retrieve copy of STATUS register
        MOVWF   STATUS        ; restore pre-isr STATUS register contents
        SWAPF   W_TEMP,f
        SWAPF   W_TEMP,w      ; restore pre-isr W register contents
        BSF INTCON,GIE
        RETFIE                ; return from interrupt

;------------------------------------------------------------------------------
; MAIN PROGRAM
;------------------------------------------------------------------------------

MAIN_PROG     CODE

START
; 	org	0x04

; Initialisation et configuration des E/S
;---------------input output control----------
  BANKSEL IOC
	movlw	B'01110001'		; 500kHz, int osc sys clk,
    movwf   OSCCON             ;osc control
	movlw	B'00000100'		; définition des IRQ
    movwf   IOC             ;select interup pin GP2 (step)
 BANKSEL (GPIO) ;select bank of portA
 CLRF    GPIO ;init PORTA
 MOVLW 07h
 MOVWF CMCON0
 BANKSEL (TRISIO) ;select bank of TRISA  data direction 1=in 0=out
 BCF WPU , phase_A 	;(pin 2 )pull up resistor
 BCF WPU , phase_B 	;(pin 2 )pull up resistor
 BCF WPU , phase_C 	;(pin 2 )pull up resistor
 BCF WPU , phase_D 	;(pin 2 )pull up resistor
 CLRF ANSEL 
 BANKSEL (GPIO) ;select bank of portA
 CLRF    GPIO ;init PORTA
 BANKSEL (TRISIO) ;select bank of TRISA  data direction 1=in 0=out
 BCF TRISIO , phase_A ;
 BCF TRISIO , phase_B ;
 BCF TRISIO , phase_C ;
 BCF TRISIO , phase_D ;
 BSF TRISIO , P_STEP ;
 BSF TRISIO , P_DIR ;
; BCF WPUA , P_BAT_IN 	;(pin 2 )pull up resistor

;	movwf	OSCCAL			; calibration de l'oscillateur RC interne
; 	clrf	GPIO
;	movlw	B'00001100'		; définition du sens des E/S
;	TRIS	GPIO
;	movlw	B'10010101' 		; pas de réveil sur changement d'état des pattes
;	OPTION 				; tirage au niveau haut activés et tmr0 / 64
 BANKSEL 	(TMR0)				; modifier tmr0/X pour des vitesses de pas différentes
	clrf	stepcount
	clrf	TMR0
 BANKSEL INTCON
    bsf INTCON,GPIE   ;set GPIE
    bsf INTCON,INTE   ;rst INTE
    bsf INTCON,GIE   ;set GIE
 MOVWF stepcount
 CALL Table_fullstep
; CALL Table halfstep ;halfstep mode
 MOVWF GPIO
;init timer function for pwm control after 5 minutes
; page 45
  BANKSEL IOC
	movlw	B'01000111'		; définition du timer
    movwf   OPTION_REG             ;osc control


	goto	main

;Table fullstep
Table_fullstep
	addwf	PCL,f
	retlw	b'00100010'
	retlw	b'00010010'
	retlw	b'00010001'
	retlw	b'00100001'

Table_halfstep
	addwf	PCL,f
	retlw	b'00100000'
	retlw	b'00100010'
	retlw	b'00000010'
	retlw	b'00010010'
	retlw	b'00010000'
	retlw	b'00010001'
	retlw	b'00000001'
	retlw	b'00100001'

; Boucle principale du programme


main
 incfsz tmrbyte1,f
 goto gpioflag
 incfsz tmrbyte2,f
 goto gpioflag
 incfsz tmrbyte3,f
 goto gpioflag
 BSF tmrstatus,0x00 ; set pwm mode
startpwm
 incfsz pwmcounter,F
 goto end_int2
 BTFSC tmrstatus,0x01 ;check time laps for pwm
 goto pwmtmr1
 BANKSEL GPIO ;select bank of portA
 CLRF GPIO
 BSF tmrstatus,0x01 ;check time laps for pwm=1
 goto end_int2
pwmtmr1

 BTFSS tmrstatus,0x01 ;check time laps for pwm
 goto pwmtmr2
 BCF tmrstatus,0x01 ;check time laps for pwm =0
 MOVF steps,W
 BANKSEL GPIO ;select bank of portA
 MOVWF GPIO
pwmtmr2
 BCF   tmrstatus,0x01 ;check time laps for pwm
end_int2
gpioflag
 BTFSC tmrstatus,0x00 ;check time laps for pwm
 goto startpwm
        GOTO main  ;wait for step to get interrupt active

        END                       ; directive 'end of program'

