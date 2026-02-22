#!/usr/bin/env python3
import json
import os
import random
import re
import shlex
import shutil
import subprocess
import sys
import time
import unicodedata
import builtins
import argparse

# ==========================================
# Constants
# ==========================================
IPERF_TEST_DEFAULT_PORT = 9777
IPERF_TEST_DEFAULT_DURATION = 8
IPERF_TEST_DEFAULT_STREAMS = 8
IPERF_MULTI_PORT_TARGET_COUNT = 100
IPERF_MULTI_PORT_TOP_COUNT = 5
IPERF_MULTI_PORT_REQUIRED = [443, 80, 9999, 2053, 2095, 2086]
IPERF_TEST_MSS = 1300
IPERF_GOOD_MBPS = 150.0
IPERF_EXCELLENT_MBPS = 200.0
IPERF_POOR_MBPS = 100.0

# ==========================================
# UI & CLI Helpers
# ==========================================
class Colors:
    HEADER = "\033[95m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    WARNING = "\033[93m"
    FAIL = "\033[91m"
    ENDC = "\033[0m"
    BOLD = "\033[1m"
    UNDERLINE = "\033[4m"

ANSI_ESCAPE_PATTERN = re.compile(r"\x1b\[[0-9;]*m")

try:
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(errors="replace")
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
except Exception:
    pass

_ORIGINAL_INPUT = builtins.input

def safe_input(prompt=""):
    try:
        return _ORIGINAL_INPUT(prompt)
    except UnicodeDecodeError:
        if prompt:
            print(prompt, end="", flush=True)
        raw = sys.stdin.buffer.readline()
        if raw == b"":
            raise EOFError
        encoding = getattr(sys.stdin, "encoding", None) or "utf-8"
        return raw.decode(encoding, errors="replace").rstrip("\r\n")

builtins.input = safe_input

def _char_display_width(ch):
    if ch in {"\u200c", "\u200d", "\ufe0e", "\ufe0f"}:
        return 0
    if unicodedata.combining(ch):
        return 0
    if unicodedata.category(ch) in {"Cf", "Mn", "Me"}:
        return 0
    if unicodedata.east_asian_width(ch) in {"F", "W"}:
        return 2
    return 1

def visible_len(text):
    clean = ANSI_ESCAPE_PATTERN.sub("", str(text))
    return sum(_char_display_width(ch) for ch in clean)

def pad_visible(text, width):
    raw = str(text)
    return raw + (" " * max(0, width - visible_len(raw)))

def print_3d_panel(title, lines=None, color=Colors.CYAN, min_width=52):
    panel_lines = [f"{Colors.BOLD}{title}{Colors.ENDC}"]
    panel_lines.extend(str(line) for line in (lines or []))
    inner_width = max(min_width, max(visible_len(line) for line in panel_lines))
    horizontal = "━" * (inner_width + 2)

    print("")
    print(f"{color}┏{horizontal}┓{Colors.ENDC}")
    for line in panel_lines:
        print(
            f"{color}┃{Colors.ENDC} {pad_visible(line, inner_width)} "
            f"{color}┃{Colors.ENDC}{Colors.BLUE}▓{Colors.ENDC}"
        )
    print(f"{color}┗{horizontal}┛{Colors.ENDC}{Colors.BLUE}▓{Colors.ENDC}")
    print(f"{Colors.BLUE} {'▓' * (inner_width + 3)}{Colors.ENDC}")

def print_menu(title, lines, color=Colors.CYAN, min_width=52):
    print_3d_panel(title, lines=lines, color=color, min_width=min_width)

def print_header(text):
    print_3d_panel(text, color=Colors.HEADER, min_width=34)

def print_success(text):
    print(f"{Colors.GREEN}[+] {text}{Colors.ENDC}")

def print_info(text):
    print(f"{Colors.BLUE}[*] {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.FAIL}[!] {text}{Colors.ENDC}")

def input_default(prompt, default):
    val = input(f"{prompt} [{default}]: ").strip()
    return val if val else str(default)

def prompt_int(prompt, default):
    while True:
        value = input_default(prompt, default)
        try:
            return int(value)
        except ValueError:
            print_error("Please enter a valid integer.")

# ==========================================
# Command Execution Helpers
# ==========================================
def run_command_stream(command):
    return subprocess.run(command, shell=True, check=False).returncode == 0

# ==========================================
# iperf3 Core Functions
# ==========================================
def ensure_iperf3_installed():
    if shutil.which("iperf3"):
        return True

    print_info("iperf3 is not installed. Attempting automatic installation...")
    installers = []
    if shutil.which("apt-get"):
        installers = [
            "apt-get update",
            "DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3",
        ]
    elif shutil.which("dnf"):
        installers = ["dnf install -y iperf3"]
    elif shutil.which("yum"):
        installers = ["yum install -y iperf3"]
    elif shutil.which("apk"):
        installers = ["apk add --no-cache iperf3"]
    elif shutil.which("pacman"):
        installers = ["pacman -Sy --noconfirm iperf3"]
    elif shutil.which("zypper"):
        installers = ["zypper --non-interactive install iperf3"]

    if not installers:
        print_error("Could not detect package manager. Please install iperf3 manually.")
        return False

    for cmd in installers:
        if not run_command_stream(cmd):
            print_error(f"Installation command failed: {cmd}")
            return False
    if not shutil.which("iperf3"):
        print_error("iperf3 installation finished but binary was not found in PATH.")
        return False
    print_success("iperf3 installed successfully.")
    return True

def run_iperf3_json(command_args):
    try:
        result = subprocess.run(command_args, check=False, text=True, capture_output=True)
    except Exception as exc:
        return None, f"failed to run iperf3: {exc}"

    stdout = (result.stdout or "").strip()
    stderr = (result.stderr or "").strip()
    if result.returncode != 0:
        return None, stderr or stdout or "iperf3 exited with non-zero status"

    try:
        payload = json.loads(stdout)
    except Exception:
        snippet = stdout[:220] + ("..." if len(stdout) > 220 else "")
        return None, f"failed to parse iperf3 json output: {snippet}"

    if isinstance(payload, dict) and payload.get("error"):
        return None, str(payload.get("error"))
    return payload, ""

def parse_port_list_csv(raw):
    seen = set()
    ports = []
    invalid = []
    for token in str(raw or "").split(","):
        part = token.strip()
        if not part:
            continue
        if not part.isdigit():
            invalid.append(part)
            continue
        port = int(part)
        if port < 1 or port > 65535:
            invalid.append(part)
            continue
        if port in seen:
            continue
        seen.add(port)
        ports.append(port)
    return ports, invalid

def extract_iperf_summary(payload):
    end = payload.get("end", {}) if isinstance(payload, dict) else {}
    sent_bps = float(end.get("sum_sent", {}).get("bits_per_second", 0.0) or 0.0)
    recv_bps = float(end.get("sum_received", {}).get("bits_per_second", 0.0) or 0.0)
    retr = int(end.get("sum_sent", {}).get("retransmits", 0) or 0)
    effective_bps = recv_bps if recv_bps > 0 else sent_bps
    return {
        "sent_mbps": sent_bps / 1_000_000.0,
        "recv_mbps": recv_bps / 1_000_000.0,
        "effective_mbps": effective_bps / 1_000_000.0,
        "retransmits": retr,
    }

def evaluate_connectivity_quality(uplink_mbps, downlink_mbps):
    floor = min(uplink_mbps, downlink_mbps)
    if floor >= IPERF_EXCELLENT_MBPS:
        return (
            "excellent",
            "Direct connectivity quality is excellent. Servers can be tunneled.",
        )
    if floor >= IPERF_GOOD_MBPS:
        return (
            "good",
            "Direct connectivity quality is good. Servers can be tunneled.",
        )
    if floor < IPERF_POOR_MBPS:
        return (
            "poor",
            "Direct connectivity is weak (<100 Mbps). Swap Iran/Kharej servers and test again.",
        )
    return (
        "moderate",
        "Direct connectivity is moderate. Tunnel can work, but quality may vary by route and load.",
    )

def run_direct_connectivity_measurement(target_host, port, duration, streams):
    base_cmd = [
        "iperf3",
        "-c",
        target_host,
        "-p",
        str(port),
        "-t",
        str(duration),
        "-P",
        str(streams),
        "-M",
        str(IPERF_TEST_MSS),
        "-J",
    ]

    down_payload, down_err = run_iperf3_json(base_cmd + ["-R"])
    if down_payload is None:
        return None, f"Downlink test failed: {down_err}"

    up_payload, up_err = run_iperf3_json(base_cmd)
    if up_payload is None:
        return None, f"Uplink test failed: {up_err}"

    down = extract_iperf_summary(down_payload)
    up = extract_iperf_summary(up_payload)
    down_mbps = down["effective_mbps"]
    up_mbps = up["effective_mbps"]
    quality, _ = evaluate_connectivity_quality(up_mbps, down_mbps)

    return {
        "port": int(port),
        "downlink_mbps": down_mbps,
        "uplink_mbps": up_mbps,
        "score_mbps": min(up_mbps, down_mbps),
        "quality": quality,
        "retransmits_up": up["retransmits"],
        "retransmits_down": down["retransmits"],
    }, ""

def run_direct_connectivity_benchmark(target_host, port, duration, streams):
    if not ensure_iperf3_installed():
        return None

    print_header("🌐 Direct Connectivity Benchmark (iperf3)")
    print_info(
        f"Target={target_host}:{port} | Duration={duration}s | Streams={streams} | MSS={IPERF_TEST_MSS} | Mode=direct (no tunnel)"
    )

    print_info("Running downlink + uplink test...")
    result, err = run_direct_connectivity_measurement(target_host, int(port), int(duration), int(streams))
    if result is None:
        print_error(err)
        print_info(
            "Ensure remote iperf3 server is running: `iperf3 -s -p "
            f"{port}`"
        )
        return None

    down_mbps = result["downlink_mbps"]
    up_mbps = result["uplink_mbps"]

    quality, verdict = evaluate_connectivity_quality(up_mbps, down_mbps)
    quality_label = {
        "excellent": f"{Colors.GREEN}excellent{Colors.ENDC}",
        "good": f"{Colors.GREEN}good{Colors.ENDC}",
        "moderate": f"{Colors.WARNING}moderate{Colors.ENDC}",
        "poor": f"{Colors.FAIL}poor{Colors.ENDC}",
    }.get(quality, quality)

    print_header("📈 Direct Connectivity Result")
    print(f"Downlink (remote -> local): {Colors.BOLD}{down_mbps:.2f} Mbps{Colors.ENDC}")
    print(f"Uplink   (local -> remote): {Colors.BOLD}{up_mbps:.2f} Mbps{Colors.ENDC}")
    print(
        f"Retransmits (uplink/downlink sender): "
        f"{Colors.BOLD}{result['retransmits_up']}/{result['retransmits_down']}{Colors.ENDC}"
    )
    print(f"Quality: {quality_label}")
    print_info(verdict)
    return {
        "port": int(port),
        "downlink_mbps": down_mbps,
        "uplink_mbps": up_mbps,
        "quality": quality,
    }

def build_multi_port_candidate_list(target_count):
    target = max(int(target_count), len(IPERF_MULTI_PORT_REQUIRED))
    ports = []
    seen = set()
    for port in IPERF_MULTI_PORT_REQUIRED:
        if 1 <= int(port) <= 65535 and port not in seen:
            seen.add(port)
            ports.append(int(port))
    while len(ports) < target:
        port = random.randint(1024, 65535)
        if port in seen:
            continue
        seen.add(port)
        ports.append(port)
    return ports

def start_iperf3_server_on_port(port):
    proc = subprocess.Popen(
        ["iperf3", "-s", "-p", str(int(port))],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.08)
    if proc.poll() is None:
        return proc
    return None

def stop_iperf3_servers(server_procs):
    for _, proc in server_procs:
        if proc is None:
            continue
        if proc.poll() is not None:
            continue
        try:
            proc.terminate()
        except Exception:
            pass
    for _, proc in server_procs:
        if proc is None:
            continue
        if proc.poll() is not None:
            continue
        try:
            proc.wait(timeout=2.0)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass

def run_multi_port_server_mode():
    if not ensure_iperf3_installed():
        return

    target_count = IPERF_MULTI_PORT_TARGET_COUNT
    initial_candidates = build_multi_port_candidate_list(target_count)
    started = []
    failed_count = 0
    attempted = set()
    required_failed = []

    def try_start(port):
        nonlocal failed_count
        p = int(port)
        if p in attempted:
            return False
        attempted.add(p)
        proc = start_iperf3_server_on_port(p)
        if proc is None:
            failed_count += 1
            return False
        started.append((p, proc))
        return True

    for p in initial_candidates:
        if len(started) >= target_count:
            break
        ok = try_start(p)
        if (p in IPERF_MULTI_PORT_REQUIRED) and not ok:
            required_failed.append(p)

    refill_guard = 0
    while len(started) < target_count and refill_guard < 10000:
        refill_guard += 1
        p = random.randint(1024, 65535)
        try_start(p)

    started_ports = [port for port, _ in started]
    if not started_ports:
        print_error("Failed to start any iperf3 server port.")
        return

    print_success(
        f"Started iperf3 server listeners on {len(started_ports)} ports "
        f"(failed attempts={failed_count})."
    )
    if required_failed:
        print_error(
            "Could not bind required ports: " + ",".join(str(p) for p in required_failed)
        )
    csv_ports = ",".join(str(p) for p in started_ports)
    print_header("📋 Port List For Client")
    print(csv_ports)
    print_info("Copy the exact comma-separated list to the client benchmark mode.")
    print_info("Press Ctrl+C to stop all started iperf3 servers.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        stop_iperf3_servers(started)
        print_info("Stopped all started iperf3 server listeners.")

def run_multi_port_client_benchmark(target_host, ports, duration, streams):
    if not ensure_iperf3_installed():
        return None
    if not ports:
        print_error("Port list is empty.")
        return None

    total = len(ports)
    print_header("🌐 Multi-Port Direct Connectivity Benchmark")
    print_info(
        f"Target={target_host} | Ports={total} | Duration={duration}s | "
        f"Streams={streams} | MSS={IPERF_TEST_MSS}"
    )

    results = []
    failed = []
    for index, port in enumerate(ports, start=1):
        print_info(f"[{index}/{total}] Testing {target_host}:{port} ...")
        result, err = run_direct_connectivity_measurement(
            target_host,
            int(port),
            int(duration),
            int(streams),
        )
        if result is None:
            failed.append((int(port), err))
            print_error(f"[{index}/{total}] port={int(port)} failed: {err}")
            continue

        results.append(result)
        print_success(
            f"[{index}/{total}] port={result['port']} "
            f"score={result['score_mbps']:.2f} Mbps "
            f"down={result['downlink_mbps']:.2f} Mbps "
            f"up={result['uplink_mbps']:.2f} Mbps "
            f"retrans(up/down)={result['retransmits_up']}/{result['retransmits_down']} "
            f"quality={result['quality']}"
        )

    if not results:
        print_error("All port tests failed.")
        if failed:
            print_info(f"First error: {failed[0][0]} -> {failed[0][1]}")
        return None

    ranked = sorted(
        results,
        key=lambda x: (x.get("score_mbps", 0.0), x.get("downlink_mbps", 0.0), x.get("uplink_mbps", 0.0)),
        reverse=True,
    )
    top_count = min(IPERF_MULTI_PORT_TOP_COUNT, len(ranked))

    print_header(f"🏆 Top {top_count} Ports")
    for idx, row in enumerate(ranked[:top_count], start=1):
        print(
            f"{idx}. port={row['port']} "
            f"score={row['score_mbps']:.2f} Mbps "
            f"down={row['downlink_mbps']:.2f} Mbps "
            f"up={row['uplink_mbps']:.2f} Mbps "
            f"quality={row['quality']}"
        )

    print_info(f"Successful tests: {len(results)}/{total}")
    if failed:
        print_info(f"Failed tests: {len(failed)} (showing up to 10 ports)")
        print_info(",".join(str(p) for p, _ in failed[:10]))

    return ranked

def direct_connectivity_test_menu(default_host=""):
    while True:
        print_menu(
            "🌐 Direct Connectivity Test (iperf3)",
            [
                "1. Start iperf3 server mode on this node",
                "2. Run client benchmark to remote node",
                "0. Exit",
            ],
            color=Colors.CYAN,
            min_width=56,
        )
        choice = input("Select option: ").strip()
        if choice == "0":
            return
        if choice == "1":
            if not ensure_iperf3_installed():
                input("\nPress Enter to continue...")
                continue
            print_menu(
                "🖥️ iperf3 Server Mode",
                [
                    "1. Single-port server",
                    f"2. Multi-port server ({IPERF_MULTI_PORT_TARGET_COUNT} ports, includes common ports)",
                    "0. Back",
                ],
                color=Colors.CYAN,
                min_width=64,
            )
            server_mode = input("Select mode: ").strip()
            if server_mode == "0":
                continue
            if server_mode == "1":
                port = prompt_int("Listen Port", IPERF_TEST_DEFAULT_PORT)
                while port < 1 or port > 65535:
                    print_error("Port must be between 1 and 65535.")
                    port = prompt_int("Listen Port", IPERF_TEST_DEFAULT_PORT)
                print_info(
                    f"Starting iperf3 server on :{port} (Ctrl+C to stop)..."
                )
                try:
                    run_command_stream(f"iperf3 -s -p {int(port)}")
                except KeyboardInterrupt:
                    pass
            elif server_mode == "2":
                run_multi_port_server_mode()
            else:
                print_error("Invalid mode.")
            input("\nPress Enter to continue...")
            continue
        if choice == "2":
            host_seed = default_host or "1.2.3.4"
            target_host = input_default("Remote server host/IP", host_seed).strip()
            while not target_host:
                print_error("Remote host is required.")
                target_host = input_default("Remote server host/IP", host_seed).strip()

            print_menu(
                "🧪 Client Benchmark Mode",
                [
                    "1. Single-port benchmark",
                    f"2. Multi-port benchmark (rank top {IPERF_MULTI_PORT_TOP_COUNT})",
                    "0. Back",
                ],
                color=Colors.CYAN,
                min_width=60,
            )
            client_mode = input("Select mode: ").strip()
            if client_mode == "0":
                continue

            duration = prompt_int("Test duration per port (seconds)", IPERF_TEST_DEFAULT_DURATION)
            streams = prompt_int("Parallel streams", IPERF_TEST_DEFAULT_STREAMS)
            if streams < 1:
                streams = 1

            if client_mode == "1":
                port = prompt_int("Remote iperf3 port", IPERF_TEST_DEFAULT_PORT)
                while port < 1 or port > 65535:
                    print_error("Port must be between 1 and 65535.")
                    port = prompt_int("Remote iperf3 port", IPERF_TEST_DEFAULT_PORT)
                run_direct_connectivity_benchmark(target_host, int(port), int(duration), int(streams))
            elif client_mode == "2":
                csv_default = ",".join(str(p) for p in IPERF_MULTI_PORT_REQUIRED)
                csv_raw = input_default("Remote iperf3 ports (comma separated)", csv_default).strip()
                ports, invalid = parse_port_list_csv(csv_raw)
                if invalid:
                    print_error(f"Ignoring invalid entries: {', '.join(invalid)}")
                if not ports:
                    print_error("No valid ports provided.")
                    input("\nPress Enter to continue...")
                    continue
                run_multi_port_client_benchmark(target_host, ports, int(duration), int(streams))
            else:
                print_error("Invalid mode.")
            input("\nPress Enter to continue...")
            continue
        print_error("Invalid choice.")


def parse_args():
    parser = argparse.ArgumentParser(description="NoDelay iperf3 Connectivity Tester")
    parser.add_argument("--mode", choices=["server", "client", "menu"], default="menu",
                        help="Run mode: server, client, or menu (interactive mode)")
    parser.add_argument("--host", type=str, help="Target host/IP (required for client mode)")
    parser.add_argument("--port", type=int, default=IPERF_TEST_DEFAULT_PORT,
                        help=f"Port for single-port test (default: {IPERF_TEST_DEFAULT_PORT})")
    parser.add_argument("--multi", action="store_true",
                        help="Enable multi-port mode for server or client")
    parser.add_argument("--ports", type=str,
                        help="Comma-separated list of ports for multi-port client test")
    parser.add_argument("--duration", type=int, default=IPERF_TEST_DEFAULT_DURATION,
                        help=f"Test duration in seconds (client mode, default: {IPERF_TEST_DEFAULT_DURATION})")
    parser.add_argument("--streams", type=int, default=IPERF_TEST_DEFAULT_STREAMS,
                        help=f"Number of parallel streams (client mode, default: {IPERF_TEST_DEFAULT_STREAMS})")
    return parser.parse_args()


def main():
    args = parse_args()

    if args.mode == "menu":
        direct_connectivity_test_menu()
    
    elif args.mode == "server":
        if not ensure_iperf3_installed():
            sys.exit(1)
        if args.multi:
            run_multi_port_server_mode()
        else:
            print_info(f"Starting iperf3 server on :{args.port} (Ctrl+C to stop)...")
            try:
                run_command_stream(f"iperf3 -s -p {args.port}")
            except KeyboardInterrupt:
                pass
                
    elif args.mode == "client":
        if not ensure_iperf3_installed():
            sys.exit(1)
        if not args.host:
            print_error("Error: --host is required when running in client mode.")
            sys.exit(1)

        if args.multi:
            if args.ports:
                ports, invalid = parse_port_list_csv(args.ports)
                if invalid:
                    print_error(f"Ignoring invalid ports: {', '.join(invalid)}")
            else:
                ports = IPERF_MULTI_PORT_REQUIRED
            
            if not ports:
                print_error("Error: No valid ports provided for multi-port test.")
                sys.exit(1)
            
            run_multi_port_client_benchmark(args.host, ports, args.duration, args.streams)
        else:
            run_direct_connectivity_benchmark(args.host, args.port, args.duration, args.streams)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nExiting...")
        sys.exit(0)
