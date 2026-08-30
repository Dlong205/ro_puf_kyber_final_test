#!/usr/bin/env python3
"""
uart_host.py — Host-side automation for RO-PUF + Kyber KEM SoC
Usage:
  python3 uart_host.py --port /dev/ttyUSBx enroll
  python3 uart_host.py --port /dev/ttyUSBx reconstruct
  python3 uart_host.py --port /dev/ttyUSBx stress --count 10000
"""

import argparse
import serial
import time
import sys
import os

BAUD = 115200
TIMEOUT = 10  # seconds
KYBER_RESPONSE_TIMEOUT = 45  # Covers the firmware's bounded retry window.

CMD_INFO   = 0x00
CMD_ENROLL = 0x01
CMD_RECON  = 0x02
STATUS_SUCCESS = 0xAA
STATUS_FAIL    = 0xFF
RESULT_KEY_FOLLOWS = 1 << 0

ERROR_NAMES = {
    0x01: "UART receive timeout",
    0x02: "PUF timeout",
    0x03: "fuzzy extractor timeout",
    0x04: "fuzzy extractor decode failure",
    0x05: "KDF timeout",
    0x06: "Kyber configuration error",
    0x07: "Kyber timeout",
    0x08: "Kyber server/client key mismatch",
}

HELPER_FILE = "helper.bin"


def open_port(port_name):
    """Open serial port with proper settings."""
    ser = serial.Serial(
        port=port_name,
        baudrate=BAUD,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=TIMEOUT
    )
    return ser


def wait_for_start(ser):
    """Wait for 'START' banner from firmware after reset."""
    print("[*] Waiting for firmware START banner...")
    buf = b""
    t0 = time.time()
    while time.time() - t0 < TIMEOUT:
        ch = ser.read(1)
        if ch:
            buf += ch
            if buf.endswith(b"START"):
                print("[+] Firmware ready!")
                return True
    print("[-] Timeout waiting for START")
    return False


def discard_stale_rx(ser):
    """Discard bytes left from an earlier command without requiring a reset banner."""
    # USB-UART drivers can deliver bytes a little after open(). Waiting before
    # inspecting in_waiting prevents a late START/line-noise byte from being
    # mistaken for the first byte of helper data.
    time.sleep(0.10)
    waiting = ser.in_waiting
    if waiting:
        stale = ser.read(waiting)
        print(f"[*] Discarded {len(stale)} stale RX byte(s): {stale!r}")


def report_firmware_failure(ser, context):
    """Consume and report the protocol-v1 error code after STATUS_FAIL."""
    code = ser.read(1)
    if not code:
        print(f"[-] Firmware reported FAIL during {context} without an error code")
        return
    name = ERROR_NAMES.get(code[0], "unknown error")
    print(f"[-] Firmware reported FAIL during {context}: 0x{code[0]:02x} ({name})")


def do_info(ser):
    """Read protocol version and release capabilities."""
    ser.write(bytes([CMD_INFO]))
    response = ser.read(5)
    if len(response) != 5 or response[:2] != b"KP":
        print(f"[-] Invalid INFO response: {response!r}")
        return False
    major, minor, capabilities = response[2], response[3], response[4]
    print(f"[+] Protocol {major}.{minor}, capabilities=0x{capabilities:02x}")
    print(f"    Shared-secret export: {'enabled (diagnostic)' if capabilities & 1 else 'disabled (release)'}")
    print(f"    Session diversification: {'yes' if capabilities & 2 else 'no'}")
    print(f"    Kyber zeroize command: {'yes' if capabilities & 4 else 'no'}")
    print(f"    Bounded Kyber retry: {'yes' if capabilities & 8 else 'no'}")
    return major == 1


def do_enroll(ser, helper_file):
    """Send ENROLL command, receive 33 bytes of helper data."""
    print("[*] Sending ENROLL command (0x01)...")
    ser.write(bytes([CMD_ENROLL]))
    
    status = ser.read(1)
    if status == bytes([STATUS_FAIL]):
        report_firmware_failure(ser, "enrollment")
        return None
    if status != bytes([STATUS_SUCCESS]):
        print(f"[-] Invalid enrollment status: {status!r}")
        return None

    # Read 33 bytes helper data (8 words * 4 bytes + 1 byte).
    helper = ser.read(33)
    if len(helper) != 33:
        print(f"[-] Expected 33 bytes helper data, got {len(helper)}")
        return None
    
    print(f"[+] Received {len(helper)} bytes helper data")
    print(f"    Hex: {helper.hex()}")
    
    # Save to file
    with open(helper_file, "wb") as f:
        f.write(helper)
    print(f"[+] Saved to {helper_file}")
    
    return helper


def do_reconstruct(ser, helper_file, helper_data=None, verbose=True):
    """Send RECONSTRUCT command with helper data, receive shared key."""
    if helper_data is None:
        if not os.path.exists(helper_file):
            print(f"[-] No helper data. Run 'enroll' first or provide {helper_file}")
            return None
        with open(helper_file, "rb") as f:
            helper_data = f.read()
    
    if len(helper_data) != 33:
        print(f"[-] Helper data must be 33 bytes, got {len(helper_data)}")
        return None
    
    if verbose:
        print("[*] Sending RECONSTRUCT command (0x02)...")
    ser.write(bytes([CMD_RECON]))
    
    # Wait for 'X' (ready for helper data)
    ch = ser.read(1)
    if ch == bytes([STATUS_FAIL]):
        report_firmware_failure(ser, "helper handshake")
        return None
    if ch != b'X':
        print(f"[-] Expected 'X', got {ch}")
        return None
    if verbose:
        print("[+] Received 'X' — sending helper data...")
    
    # Send helper data word by word (8 words + 1 byte)
    for w in range(8):
        chunk = helper_data[w*4:(w+1)*4]
        ser.write(chunk)
        ack = ser.read(1)
        if ack == bytes([STATUS_FAIL]):
            report_firmware_failure(ser, f"helper word {w}")
            return None
        expected_ack = chr(ord('0') + w).encode()
        if ack != expected_ack:
            print(f"[-] Word {w}: expected ack '{expected_ack}', got '{ack}'")
            return None
    
    # Send last byte
    ser.write(helper_data[32:33])
    ack = ser.read(1)
    if ack == bytes([STATUS_FAIL]):
        report_firmware_failure(ser, "last helper byte")
        return None
    if ack != b'8':
        print(f"[-] Last byte: expected '8', got '{ack}'")
        return None
    
    # Read progress markers: A, B, C, D, E, F, G. Firmware can emit
    # STATUS_FAIL immediately after C (FE failure) or F (Kyber failure).
    progress = ""
    for marker in "ABCDEFG":
        # A raw Kyber attempt may be reset and retried after marker F. Keep
        # normal UART operations responsive while allowing the bounded retry
        # window only for the final Kyber marker.
        previous_timeout = ser.timeout
        if marker == "G":
            ser.timeout = KYBER_RESPONSE_TIMEOUT
        ch = ser.read(1)
        ser.timeout = previous_timeout
        if not ch:
            print(f"[-] Timeout waiting for marker '{marker}' (got so far: {progress})")
            return None
        if ch[0] == STATUS_FAIL:
            report_firmware_failure(ser, f"pipeline after markers {progress}")
            return None
        if ch != marker.encode():
            print(
                f"[-] Protocol error: expected marker '{marker}', got 0x{ch[0]:02x} "
                f"(got so far: {progress})"
            )
            return None
        progress += marker
    if verbose:
        print(f"[+] Progress: {progress}")
    
    # Read status byte
    status = ser.read(1)
    if not status:
        print("[-] Timeout waiting for status byte")
        return None
    
    status_val = status[0]
    if status_val == STATUS_SUCCESS:
        flags = ser.read(1)
        if not flags:
            print("[-] Missing success result flags")
            return None
        if flags[0] & ~RESULT_KEY_FOLLOWS:
            print(f"[-] Unsupported result flags: 0x{flags[0]:02x}")
            return None
        if flags[0] & RESULT_KEY_FOLLOWS:
            key = ser.read(32)
            if len(key) != 32:
                print(f"[-] Expected 32 bytes key, got {len(key)}")
                return None
            if verbose:
                print("[+] SUCCESS! Diagnostic shared key (256-bit):")
                print(f"    {key.hex()}")
        else:
            key = b""
            if verbose:
                print("[+] SUCCESS! Server/client keys matched; release firmware withheld the secret")
        return key
    elif status_val == STATUS_FAIL:
        report_firmware_failure(ser, "final status")
        return None
    else:
        print(f"[-] Unknown status: 0x{status_val:02x}")
        return None


def do_stress(ser, count, helper_file):
    """Run enroll once, then reconstruct N times."""
    print(f"[*] Stress test: {count} iterations")
    
    # First do enroll
    helper = do_enroll(ser, helper_file)
    if helper is None:
        print("[-] Enroll failed, aborting stress test")
        return False
    
    pass_count = 0
    fail_count = 0
    reference_key = None
    aborted = False
    
    for i in range(count):
        key = do_reconstruct(ser, helper_file, helper, verbose=False)
        if key is not None:
            if reference_key is None:
                reference_key = key
            if key == reference_key:
                pass_count += 1
            else:
                fail_count += 1
                print(f"  [!] Iteration {i+1}: Key mismatch!")
                if key:
                    print(f"      Expected: {reference_key.hex()}")
                    print(f"      Got:      {key.hex()}")
        else:
            fail_count += 1
            print(f"  [!] Iteration {i+1}: Reconstruct failed")
            print("  [!] Aborting to preserve protocol synchronization")
            aborted = True
        
        if (i + 1) % 100 == 0:
            print(f"  [{i+1}/{count}] Pass={pass_count} Fail={fail_count}")
        if aborted:
            break
    
    print(f"\n=== STRESS TEST RESULTS ===")
    attempted = pass_count + fail_count
    print(f"  Requested: {count}")
    print(f"  Attempted: {attempted}")
    print(f"  Pass:   {pass_count}")
    print(f"  Fail:   {fail_count}")
    print(f"  Rate:   {pass_count/attempted*100:.2f}%")
    
    if fail_count == 0:
        print("  *** ALL PASSED ***")
        return True
    else:
        print("  *** SOME FAILURES DETECTED ***")
        return False


def main():
    parser = argparse.ArgumentParser(description="RO-PUF + Kyber SoC Host Tool")
    parser.add_argument("--port", "-p", required=True, help="Serial port (e.g., /dev/ttyUSB0)")
    parser.add_argument(
        "--wait-start",
        action="store_true",
        help="Require the one-time START banner (open the port before FPGA reset/programming)",
    )
    parser.add_argument(
        "--no-wait",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--helper",
        default=HELPER_FILE,
        help=f"Helper-data file (default: {HELPER_FILE})",
    )
    
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("info", help="Read firmware protocol version and capabilities")
    sub.add_parser("enroll", help="Enroll PUF and save helper data")
    sub.add_parser("reconstruct", help="Reconstruct key from saved helper data")
    
    stress_p = sub.add_parser("stress", help="Stress test N iterations")
    stress_p.add_argument("--count", "-n", type=int, default=100, help="Number of iterations")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    try:
        ser = open_port(args.port)
    except serial.SerialException as exc:
        print(f"[-] Cannot open serial port {args.port}: {exc}")
        sys.exit(1)
    print(f"[*] Opened {args.port} @ {BAUD} baud")
    
    if args.wait_start and not args.no_wait:
        if not wait_for_start(ser):
            ser.close()
            sys.exit(1)
    else:
        # START is emitted only once after FPGA reset. Requiring it here would
        # make a second invocation (for reconstruct after enroll) fail even
        # though firmware is still ready and waiting for a command.
        discard_stale_rx(ser)
    
    ok = False
    if args.command == "info":
        ok = do_info(ser)
    elif args.command == "enroll":
        ok = do_enroll(ser, args.helper) is not None
    elif args.command == "reconstruct":
        ok = do_reconstruct(ser, args.helper) is not None
    elif args.command == "stress":
        ok = do_stress(ser, args.count, args.helper)
    
    ser.close()
    print("[*] Done.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
