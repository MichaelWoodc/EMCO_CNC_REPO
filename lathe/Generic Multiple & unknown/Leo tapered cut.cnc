File for Leo to cut taper at end of billet. Small diameter = 1.175" Large diameter = 1.582" Length between on centreline = .427"
%
    N` G`   X `    Z `  F`  H 
    00 95                       
    01M03                       
    02 92  1581     00          Tool at 1.581"diam and rub faced end
    03 91                       Change to Incremental program
    04 01 -  50     00  20      Depth of 1st cut, next cuts on by Line 23
    05 25             L 20      Jump to Sub routine
    06 25             L 20      
    07 25             L 20      
    08 25             L 20      
    09 25             L 20      
    10 25             L 20      
    11 25             L 20      
    12 25             L 20      
    13 00    08     00          
    14 92  1176     00          
    15 01  1581 -  427  02      Final taper cut
    16 00  1581     00          
    17 21                       
    18M30                       PROGRAM END
    19 21                       
    20 01   203 -  427  02      Tapered cut Sub routine
    21 00    30     00          
    22 00    00    427          
    23 00 - 253     00          
    24M17                       Return to main program
   "
