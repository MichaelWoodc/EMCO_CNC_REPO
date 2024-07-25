Material .5" brass rod, 2.5" from chuck jaws. Set spindle to 1500 rpm

Uses a sub program for multiple taper cuts, G25 nominates the next line of code to use, in this case the sub program starts at Line 15. The M17 code returns the program run line to the line immediately after the G25 command, in this case Line 07.

Line 12 returns the tool back to the program start position ready for the next piece.

mwg sept 2016

For more program demos see "ukmwg" on Youtube
%
    N` G`   X `    Z `  F`  H 
    00 21                       Machine defaults to INCREMENTAL mode. G91
    01 21                       RH tool at end face on .250" radius
    02M03                       If no M03 available Manually start spindle
    03 95                       Feed per rev (default is G94 mm or inch/min)
    04 01 - 250     00  60      Tool to centre
    05 03   250 -  250  60      .500" diam radiused end to rod
    06 00    00    250          Tool to end face
    07 25             L 15      
    08 25             L 15      
    09 25             L 15      
    10 25             L 15      
    11 25             L 15      
    12 25             L 15      
    13 00    30     00          Tool back to prog start position
    14M30                       Program END
    15 01 -  05     00  60      DOC per pass,( .010" off diameter)
    16 01    30 - 5000  60      taper cut for 50mm length
    17 00    00   5000          
    18 00 -  30     00          
    19M17                       end of sub program, Lines 15-19
   "
