#!/usr/bin/python

import os
import argparse
import serial
from msvcrt import getch

debug_mode = False

def main():
    parser = argparse.ArgumentParser(description="EMCO Transfer Tool")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--upload", default=None, type=str, help="Upload a file to the machine")
    group.add_argument("--download", default=None, type=str, help="Download a file from the machine")
    parser.add_argument("--baud", default=1200, type=int, help="baud rate for serial port")
    parser.add_argument("--port", default="COM3", type=str, help="serial port")
    parser.add_argument("--flowcontrol", default=True, type=bool, help="Turn CTS/RTS flow control on or off")
    parser.add_argument("--parity", default="N", type=str, help="Serial parity mode")
    parser.add_argument("--stopbits", default=1, type=int, help="Serial stop bits")
    parser.add_argument("--debug", default=False, type=bool, help="Show all serial output in hex")
    args = parser.parse_args()
    global debug_mode
    debug_mode = args.debug

    serial_port = open_serial(args)
    
    if args.upload != None:
        upload(args.upload, serial_port)
    elif args.download != None:
        download(serial_port, args.download)

def open_serial(args):
    serial_port = serial.Serial(args.port, args.baud, timeout=30, parity=args.parity, bytesize=8, rtscts=args.flowcontrol, stopbits=args.stopbits)
    return serial_port

def write_serial(serial_port, line, add_crlf=True):
    global debug_mode

    line = line.strip()
    if add_crlf:
        print("Sending:", line)
        line += ' \r\n'
    byte_data = line.encode()
    if debug_mode:
        debug_output = ''.join( [ "%02X " % ord( x ) for x in line ] ).strip()
        print("Hex:", debug_output)
    serial_port.write(byte_data)

# copy the file at <filename> to the serial port at <serial>
def upload(filename, serial_port):
    print("uploading %s" % filename)

    step_mode = False
    print("Step mode? (y/N) ", end='', flush=True)
    ch = getch()
    if ch == 'y' or ch == 'Y':
        print("yes")
        step_mode = True
    else:
        print("no")

    with open(filename, "r") as file:
        for line in file:
            write_serial(serial_port, line)
            if step_mode:
                print("Paused, press any key...")
                getch()

    # control-Z for end of program
    write_serial(serial_port, '\x1A', add_crlf=False)
    print("Done!")

# copy data from the serial port at <serial> to the file with <filename>
# not really tested, we never use this functionality
def download(serial_port, filename):
    print("downloading %s" % filename)

    with open(filename, "w") as file:
        done = False
        while not done:
            lines = serial_port.readlines()

            for line in lines:
                line.replace('\x05', '')
                line.replace('\x0E', '')
                file.write(line)

            if len(lines) == 0:
                done = True

if __name__ == "__main__":
    main()


    
