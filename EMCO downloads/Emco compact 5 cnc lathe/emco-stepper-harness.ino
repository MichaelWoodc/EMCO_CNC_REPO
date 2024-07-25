/*
 * EMCO Schrittmotorplatine (stepper motor driver board) test harness.
 * 
 * Generates a four phase test signal as input to an A6A 113 001
 * stepper motor driver board.
 * 
 * Originally for Arduino Duemilanovae.
 *
 * Stephen Davies
 * September 2018 
 */

// Output pin assignments
// Connect to X32 or X34
const int A = 3;
const int B = 4;
const int C = 5;
const int D = 6;

// Stepper motor pulse width (ms)
const int PULSE_WIDTH = 200;

// A & B on initially
byte data = 0xCC;

void setup() {
  pinMode(A, OUTPUT);
  pinMode(B, OUTPUT);
  pinMode(C, OUTPUT);
  pinMode(D, OUTPUT);
}

void loop() {
  if (data & 0x80) {
    // high bit is set, rotate it through
    data <<= 1;
    data |= 1;
  } else {
    // high bit clear, no rotate necessary
    data <<= 1;
  }

  if (data & 0x08) {
      digitalWrite(A, HIGH);
  } else {
      digitalWrite(A, LOW);
  }
  if (data & 0x04) {
      digitalWrite(B, HIGH);
  } else {
      digitalWrite(B, LOW);
  }
  if (data & 0x02) {
      digitalWrite(C, HIGH);
  } else {
      digitalWrite(C, LOW);
  }
  if (data & 0x01) {
      digitalWrite(D, HIGH);
  } else {
      digitalWrite(D, LOW);
  }

  // Divide by 2 to get 90 degrees out of phase between A/C and B/D
  delay(PULSE_WIDTH / 2);
}

