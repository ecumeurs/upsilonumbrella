#!/usr/bin/env python3
"""
Upsilon Battle Engine Stress Testing Tool.
This script orchestrates multiple concurrent matches using bot scripts to stress
the engine and monitor resource usage (CPU, Memory, FDs).

@spec-link [[mechanic_battle_engine_stress_testing]]
"""
import subprocess
import time
import os
import random
import signal
import sys
import json
from datetime import datetime
import threading
import re

# Configuration
TEST_DURATION_SECS = 600  # 10 minutes
METRICS_INTERVAL = 10     # 10 seconds
LOG_DIR = "/workspace/stress_test_logs"
REPORT_PREFIX = "stress_test_report"
NUM_MATCHES_PER_MODE = 3
CLI_BIN = "/workspace/upsiloncli/bin/upsiloncli"
BOT_SCRIPT = "/workspace/upsiloncli/samples/fast_bot_battle.js"
PARSER_BIN = "/workspace/upsiloncli/upsilon_log_parser.py"

MODES = {
    "1v1_PVP": 2,
    "2v2_PVP": 4,
    "1v1_PVE": 1,
    "2v2_PVE": 2
}

class MatchManager:
    """
    Orchestrates match lifecycle, metric collection, and report generation.
    """
    def __init__(self):
        """Initializes logs directory and discovers running system services."""
        self.matches = [] # List of {process, mode, start_time, log_file}
        self.metrics = []
        self.service_pids = {} # {service_name: pid}
        self.service_history = {} # {service_name: [mem_samples]}
        self.running = True
        self.start_time = time.time()
        
        if not os.path.exists(LOG_DIR):
            os.makedirs(LOG_DIR)
        
        self.discover_services()

    def discover_services(self):
        """
        Attempts to locate PIDs for Upsilon services (Engine, API, UI)
        by checking the .services.pids file and scanning /proc.
        """
        # 1. Try .services.pids
        pid_file = "/workspace/.services.pids"
        if os.path.exists(pid_file):
            try:
                with open(pid_file, "r") as f:
                    for line in f:
                        if "|" in line:
                            name, pid, _, _ = line.strip().split("|")
                            self.service_pids[name] = int(pid)
                            self.service_history[name] = []
            except Exception as e:
                print(f"Warning: Failed to parse {pid_file}: {e}")

        # 2. Fallback scan for missing services
        scan_map = {
            "Laravel API": "artisan serve",
            "Reverb Server": "artisan reverb",
            "Upsilon Engine": "upsilonapi",
            "Vue Frontend": "vite"
        }
        
        for name, pattern in scan_map.items():
            if name not in self.service_pids or not self.is_pid_alive(self.service_pids[name]):
                pid = self.find_pid_by_cmd(pattern)
                if pid:
                    self.service_pids[name] = pid
                    self.service_history[name] = []
                    print(f"[{datetime.now().isoformat()}] Discovered {name} at PID {pid}")

    def is_pid_alive(self, pid):
        """Checks if a given PID is currently active in the system."""
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    def find_pid_by_cmd(self, pattern):
        """Scans /proc to find a process whose command line matches the pattern."""
        try:
            for pid in os.listdir('/proc'):
                if pid.isdigit():
                    try:
                        with open(f"/proc/{pid}/cmdline", "rb") as f:
                            cmdline = f.read().replace(b'\0', b' ').decode('utf-8')
                            if pattern in cmdline and "stress_test.py" not in cmdline:
                                return int(pid)
                    except: pass
        except: pass
        return None

    def get_process_memory(self, pid):
        """
        Calculates RSS memory in MB for a specific PID by reading /proc/[pid]/statm.
        """
        """Returns RSS memory in MB for a PID."""
        try:
            # /proc/[pid]/statm: size resident shared text lib data dirty
            # Second field is resident set size (RSS) in pages
            with open(f"/proc/{pid}/statm", "r") as f:
                pages = int(f.read().split()[1])
                return (pages * 4096) / (1024 * 1024) # Assuming 4KB page size
        except:
            return 0

    def start_match(self, mode):
        """
        Spawns a new upsiloncli process for a specific game mode and redirects output to logs.
        """
        num_bots = MODES[mode]
        match_id = f"{mode}_{int(time.time() * 1000)}_{random.randint(100, 999)}"
        log_file = os.path.join(LOG_DIR, f"{match_id}.log")
        
        # Build command
        # UPSILON_BASE_URL is inherited from the environment (set at compose
        # level to the Caddy front door); the CLI's --local flag was removed
        # post-auth-extraction since no scenario can run hub-direct anymore.
        cmd = [CLI_BIN, "--farm", "--timeout", "600"]
        for _ in range(num_bots):
            cmd.append(BOT_SCRIPT)
        
        env = os.environ.copy()
        env["UPSILON_GAME_MODE"] = mode
        env["REVERB_APP_KEY"] = "qtjp54myattne9euwedu"
        
        with open(log_file, "w") as f:
            proc = subprocess.Popen(cmd, env=env, stdout=f, stderr=subprocess.STDOUT)
            
        print(f"[{datetime.now().isoformat()}] Started match: {match_id} ({mode})")
        return {"process": proc, "mode": mode, "id": match_id, "start_time": time.time(), "log": log_file}

    def monitor_and_respawn(self):
        """
        Continuous loop that checks for terminated match processes and respawns
        them to maintain the desired load until the test duration ends.
        """
        while self.running and (time.time() - self.start_time < TEST_DURATION_SECS):
            # Check for finished matches
            still_running = []
            for m in self.matches:
                if m["process"].poll() is not None:
                    print(f"[{datetime.now().isoformat()}] Match {m['id']} finished. Respawning...")
                    still_running.append(self.start_match(m["mode"]))
                else:
                    still_running.append(m)
            self.matches = still_running
            time.sleep(1)

    def collect_metrics(self):
        """
        Polls system-wide and service-specific metrics (CPU, Memory, FDs)
        at regular intervals and stores them for reporting.
        """
        while self.running and (time.time() - self.start_time < TEST_DURATION_SECS):
            now = datetime.now().isoformat()
            
            # Simple global CPU via /proc/stat
            try:
                def get_cpu_times():
                    with open('/proc/stat', 'r') as f:
                        line = f.readline()
                        parts = line.split()
                        return sum(int(x) for x in parts[1:]), int(parts[4])
                
                t1_total, t1_idle = get_cpu_times()
                time.sleep(1)
                t2_total, t2_idle = get_cpu_times()
                
                total_delta = t2_total - t1_total
                idle_delta = t2_idle - t1_idle
                cpu = 100 * (1 - idle_delta / total_delta) if total_delta > 0 else 0
            except:
                cpu = 0

            # Memory via /proc/meminfo
            try:
                with open('/proc/meminfo', 'r') as f:
                    for line in f:
                        if "MemTotal" in line: total = int(line.split()[1])
                        if "MemAvailable" in line: available = int(line.split()[1])
                mem = (total - available) / 1024 # MB
            except:
                mem = 0
            
            # FDs via /proc/pid/fd
            fds = 0
            try:
                # Count own FDs
                fds += len(os.listdir('/proc/self/fd'))
                # Count children FDs (simplified)
                # In a real stress test, we'd want to iterate /proc/[pid]/fd for all children
                # For now let's just count all running 'upsiloncli' processes FDs
                for pid in os.listdir('/proc'):
                    if pid.isdigit():
                        try:
                            with open(f"/proc/{pid}/comm", "r") as f:
                                if "upsiloncli" in f.read():
                                    fds += len(os.listdir(f"/proc/{pid}/fd"))
                        except: pass
            except: pass

            metric = {
                "timestamp": now,
                "elapsed": int(time.time() - self.start_time),
                "cpu_percent": cpu,
                "mem_mb": mem,
                "open_fds": fds,
                "active_matches": len(self.matches),
                "active_bots": sum(MODES[m["mode"]] for m in self.matches),
                "service_memory": {}
            }

            # Collect service breakdown
            total_bots_mem = 0
            # Track bots (upsiloncli processes we started)
            for m in self.matches:
                if m["process"].poll() is None:
                    mem = self.get_process_memory(m["process"].pid)
                    total_bots_mem += mem
            
            metric["service_memory"]["Bots (Combined)"] = total_bots_mem
            self.service_history.setdefault("Bots (Combined)", []).append(total_bots_mem)

            # Track discovered services
            for name, pid in self.service_pids.items():
                if self.is_pid_alive(pid):
                    mem = self.get_process_memory(pid)
                    metric["service_memory"][name] = mem
                    self.service_history[name].append(mem)
                else:
                    metric["service_memory"][name] = 0

            self.metrics.append(metric)
            time.sleep(max(0, METRICS_INTERVAL - 1)) # Adjust for CPU sample sleep

    def run(self):
        """
        Primary execution loop: launches initial matches, starts monitoring threads,
        and waits for the test duration to complete.
        """
        print(f"[{datetime.now().isoformat()}] Starting stress test for {TEST_DURATION_SECS} seconds...")
        
        # Initial launch
        for mode in MODES:
            for _ in range(NUM_MATCHES_PER_MODE):
                self.matches.append(self.start_match(mode))

        # Start monitoring threads
        respawn_thread = threading.Thread(target=self.monitor_and_respawn)
        metrics_thread = threading.Thread(target=self.collect_metrics)
        
        respawn_thread.start()
        metrics_thread.start()

        # Wait for duration
        try:
            while time.time() - self.start_time < TEST_DURATION_SECS:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nInterrupt received. Stopping...")
        
        self.running = False
        respawn_thread.join(timeout=5)
        metrics_thread.join(timeout=5)
        self.teardown()

    def teardown(self):
        """Terminates all remaining match processes and triggers final report consolidation."""
        print(f"[{datetime.now().isoformat()}] Tearing down matches...")
        for m in self.matches:
            if m["process"].poll() is None:
                m["process"].terminate()
        
        # Final consolidation
        self.consolidate()

    def consolidate(self):
        """
        Aggregates logs from all matches, parses tactical events,
        calculates memory trends, and writes JSON/Markdown reports.
        """
        print(f"[{datetime.now().isoformat()}] Consolidating reports...")
        
        total_actions = 0
        total_deaths = 0
        total_errors = 0
        error_types = {}
        match_outcomes = {"VICTORY": 0, "DEFEAT": 0, "TIMEOUT": 0}
        
        all_logs = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR) if f.endswith(".log")]
        
        consolidated_tactical = []
        
        for log in all_logs:
            # Run the parser in tactical mode to get actions
            log_has_errors = False
            try:
                # Use the parser's filter mode but capture output
                res = subprocess.run([sys.executable, PARSER_BIN, log, "--tactical"], capture_output=True, text=True)
                # We also need a way to get counts. Let's just parse the output or the file again.
                # Actually, the parser prints a summary at the end.
                
                # Parse the report summary from parser output
                # (This part depends on parser output format)
                log_content = res.stdout
                
                # Counting actions/deaths/errors from tactical logs
                for line in log_content.splitlines():
                    if "Moving:" in line or "Action:" in line:
                        total_actions += 1
                    if "was eliminated" in line:
                        total_deaths += 1
                    if "ERROR:" in line:
                        total_errors += 1
                        log_has_errors = True
                        err_msg = line.split("ERROR:", 1)[1].strip()
                        error_types[err_msg] = error_types.get(err_msg, 0) + 1
                    if "RESULT: VICTORY" in line: match_outcomes["VICTORY"] += 1
                    if "RESULT: DEFEAT" in line: match_outcomes["DEFEAT"] += 1
                    if "CLOCK: TIMEOUT" in line: match_outcomes["TIMEOUT"] += 1
                    
                    if "[" in line and "]" in line:
                         consolidated_tactical.append(line)

                # Cleanup clean logs
                if not log_has_errors:
                    try:
                        os.remove(log)
                    except:
                        pass

            except Exception as e:
                print(f"Failed to parse {log}: {e}")

        # Calculate memory trends
        memory_breakdown = {}
        for name, history in self.service_history.items():
            if history:
                start_mem = history[0]
                peak_mem = max(history)
                end_mem = history[-1]
                delta = end_mem - start_mem
                memory_breakdown[name] = {
                    "start_mb": start_mem,
                    "peak_mb": peak_mem,
                    "end_mb": end_mem,
                    "delta_mb": delta,
                    "leak_risk": "HIGH" if delta > 10 and end_mem > start_mem * 1.2 else "LOW"
                }

        # Write JSON report
        report_data = {
            "test_duration_secs": TEST_DURATION_SECS,
            "total_matches": len(all_logs),
            "total_actions": total_actions,
            "total_deaths": total_deaths,
            "total_errors": total_errors,
            "error_distribution": error_types,
            "match_outcomes": match_outcomes,
            "memory_breakdown": memory_breakdown,
            "metrics": self.metrics
        }
        
        with open(f"{REPORT_PREFIX}.json", "w") as f:
            json.dump(report_data, f, indent=4)
            
        # Write Markdown report
        avg_cpu = sum(m["cpu_percent"] for m in self.metrics) / len(self.metrics) if self.metrics else 0
        max_mem = max(m["mem_mb"] for m in self.metrics) if self.metrics else 0
        
        with open(f"{REPORT_PREFIX}.md", "w") as f:
            f.write(f"# Upsilon Stress Test Report\n\n")
            f.write(f"**Date:** {datetime.now().isoformat()}\n")
            f.write(f"**Duration:** {TEST_DURATION_SECS}s\n")
            f.write(f"**Total Matches Run:** {len(all_logs)}\n\n")
            
            f.write(f"## Performance Summary\n")
            f.write(f"- **Average CPU:** {avg_cpu:.1f}%\n")
            f.write(f"- **Peak Memory:** {max_mem:.1f} MB\n")
            f.write(f"- **Max Open FDs:** {max(m['open_fds'] for m in self.metrics) if self.metrics else 0}\n\n")
            
            f.write(f"## Tactical Summary\n")
            f.write(f"- **Total Robot Actions:** {total_actions}\n")
            f.write(f"- **Total Casualties:** {total_deaths}\n")
            f.write(f"- **Clock Timeouts:** {match_outcomes['TIMEOUT']}\n")
            f.write(f"- **Success Rate (Logged Victories):** {match_outcomes['VICTORY']} wins / {match_outcomes['DEFEAT']} losses\n\n")
            
            f.write(f"## Error Report\n")
            f.write(f"- **Total Errors:** {total_errors}\n")
            if error_types:
                f.write("| Error Type | Count |\n|---|---|\n")
                for err, count in error_types.items():
                    f.write(f"| {err} | {count} |\n")
            else:
                f.write("No errors detected.\n")

            f.write(f"\n## Service Memory Breakdown\n")
            f.write("| Service | Start (MB) | Peak (MB) | End (MB) | Delta (MB) | Leak Risk |\n")
            f.write("|---|---|---|---|---|---|\n")
            for name, stats in memory_breakdown.items():
                risk_emoji = "⚠️" if stats["leak_risk"] == "HIGH" else "✅"
                f.write(f"| {name} | {stats['start_mb']:.1f} | {stats['peak_mb']:.1f} | {stats['end_mb']:.1f} | {stats['delta_mb']:+.1f} | {risk_emoji} {stats['leak_risk']} |\n")

        print(f"Final reports generated: {REPORT_PREFIX}.json, {REPORT_PREFIX}.md")

if __name__ == "__main__":
    manager = MatchManager()
    manager.run()
