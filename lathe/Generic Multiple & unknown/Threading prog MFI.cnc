Incremental program mm

X is total thread depth, for external thread use the - sign.

X is without the sin for internal thread

Z is for total length of traverse, thread length will be traverse less the distance the tool starts from the end face of job, in this case is 25mm.(tool 1mm from end)

H column is the DOC per pass

There is a maximum spindle speed when threading or you get an Alarm code A06 and the program Halts until the rpm 
is reduced/set to less than the maximum for the rate of thread, finer the thread higher the spindle speed.
350 was a guess at a suitable speed for the example, I didn't have the speed chart to hand.
This is to allow the spindle sensor to syncronise the point at which the Z command is executed and threading 
starts.
 
The A06 alarm will come on the display to indicate the spindle speed is set too high and Halt the program, if this 
happens turn the spindle speed pot down slowly until the spindle starts and the program continues.
The chart showing max spindle speeds for thread pitch is in the manual but I find the rpm below suits my use.

0.50mm/800rpm, 1.00mm/400, 1.50mm/300rpm, 1.75mm/250rpm, 2.00mm/240rpm

You may have to adjust the spindle speed by changing belt positions to achieve enough torque to reliably thread 
the coarser threads at the lower max rpm.

Use of G95 (feed per rev) has nothing to do with the threading function but used in case of a tool jamming and 
stalling the motor, if you haven't got the G95 in the program the Z axis will continue trying to force the tool 
into the stationary workpiece. 
Try it by switching the motor off during a simulated working cycle, the spindle and both axis will slow to a 
stopped position.

G95 does give a good degree of protection to the lathe and may save a workpiece being scrap.

%
    N` G`   X `    Z `  F`  H 
    00 21                       Move tool tip to diameter of thread OD
    01 21                       .move tip to 1.00mm away from endface
    02 95                       traverse stops if spindle stops
    03 21                       Manually switch motor ON, set speed 350rpm
    04 78 -  50 - 2600K100  02  @  (25x)Threading Cycle
    05 21                       end of cycle tool returns to start position
    06M30                       End of program
    07 21                       
    08 21                       
    09 21                       F column is rate of thread, metric shown
    10 21                       F column is rate of thread hundreds of mm
    11 21                       For .50mm=50, .75=75, 1.0=100, 1.25=125
    12 21                       and so forth
    13 21                       For imperial divide 1000 by TPI for F entry
    14 21                       1000/32 = 31 so .031" pitch, enter 031 F
    15 21                       so for Inch program  32TPI F=031
    16 21                       You can do the division sum in the column
    17 21                       So for 16TPI 1000/16=63 so F is 063
   M
