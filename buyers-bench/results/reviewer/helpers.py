"""Helpers the reviewer's tests use. Every test gets a FRESH, empty copy of the app (no saved data)."""
import re, subprocess, sys
from pathlib import Path
_APP = [None]


def app_dir() -> Path:
    """The folder holding catalog.py, orders.py and shop.py for this test (starts with no data files)."""
    return _APP[0]


def run(*args, cwd=None):
    """Run `python3 shop.py <args>` like Chris would. Returns (exit_code, stdout, stderr).
    cwd defaults to the app folder; pass another folder to run it from somewhere else."""
    p = subprocess.run([sys.executable, str(_APP[0] / "shop.py"), *map(str, args)], cwd=str(cwd or _APP[0]),
                       capture_output=True, text=True, timeout=20)
    return p.returncode, p.stdout, p.stderr


def money(text):
    """Every dollar amount in text, as floats: 'paid $25.00, kept 23.10' -> [25.0, 23.1]."""
    return [float(x) for x in re.findall(r"\$?\s?(-?\d+\.\d{2})\b", text)]


# --- wording-proof helpers: a correct program may phrase every message differently ---
def ok(*args, cwd=None):
    """Run a command that SHOULD succeed; fails the test (with its output) if it doesn't. Returns stdout."""
    rc, out, err = run(*args, cwd=cwd)
    assert rc == 0 and "Traceback" not in err, f"{args} failed (exit {rc}): {(err or out)[-300:]}"
    return out


def refused(*args, cwd=None):
    """Run a command that SHOULD be refused: non-zero exit code and a clean error, not a crash."""
    rc, out, err = run(*args, cwd=cwd)
    assert rc != 0, f"{args} should be refused but exited 0: {out[-200:]}"
    assert "Traceback" not in err + out, f"{args} crashed instead of a clean error"


def order_id(text):
    """The order ID the program printed after placing an order, whatever its wording."""
    ids = re.findall(r"(?i)\b(?:order\s*id|order|id)\b\s*[:#=]?\s*#?([A-Za-z0-9][A-Za-z0-9_-]*)", text)
    ids = [i for i in ids if i.lower() not in ("id", "order", "placed", "for", "created")]
    toks = re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]*", text)
    return ids[-1] if ids else (toks[-1] if toks else "")


def stock_of(sku, cwd=None):
    """How many of SKU are in stock, read from the `stock` command whatever its wording."""
    nums = re.findall(r"\b(\d+)\b", ok("stock", sku, cwd=cwd).replace(sku, ""))
    return int(nums[-1]) if nums else None
