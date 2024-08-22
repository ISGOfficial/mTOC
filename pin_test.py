# This script is in mTOC-G/scripts - adjust as necessary. This is a diagnostic tool to ensure your wiring is being recognized by the python scripts that control the power to the mTOC

import RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
pin = 3  # Adjust based on your setup
GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)  # Adjust if needed

try:
    while True:
        current_state = GPIO.input(pin)
        print(f"GPIO pin state: {current_state}")
        time.sleep(1)
except KeyboardInterrupt:
    GPIO.cleanup()
