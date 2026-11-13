#!/usr/bin/env python3
"""Run a command; after TIMEOUT seconds interrupt it (SIGINT, then SIGKILL) and exit with 124.

usage: run_with_timeout.py SECONDS -- command [args...]
SIGINT lets Bazel stop cleanly, so everything already built stays in the disk cache.
"""
import os
import signal
import subprocess
import sys
import time


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--':
        print(__doc__)
        sys.exit(2)
    timeout = float(sys.argv[1])
    process = subprocess.Popen(sys.argv[3:], start_new_session=True)
    deadline = time.time() + timeout
    while True:
        code = process.poll()
        if code is not None:
            sys.exit(code)
        if time.time() > deadline:
            break
        time.sleep(5)
    print('run_with_timeout: time limit reached, stopping the build', flush=True)
    os.killpg(process.pid, signal.SIGINT)
    try:
        process.wait(timeout=180)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(124)


if __name__ == '__main__':
    main()
