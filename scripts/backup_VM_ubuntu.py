#!/usr/bin/env python3
    # Script Python pentru efectuarea backup-ului logurilor de sistem.

import os, sys, time, json, shutil, signal, logging, hashlib
from datetime import datetime, timezone
from pathlib import Path

# Configurare variabile de mediu
SOURCE_FILE = os.environ.get("SOURCE_FILE") or os.environ.get("LOG_FILE") or "logs/VM-state.log"
BACKUP_DIR = os.environ.get("BACKUP_DIR", "backup")
BACKUP_INTERVAL = os.environ.get("BACKUP_INTERVAL") or os.environ.get("INTERVAL_BACKUP") or "5"

try:
    BACKUP_INTERVAL_S = max(1, int(BACKUP_INTERVAL))
except Exception:
    BACKUP_INTERVAL_S = 5 
        # Validam ca BACKUP_INTERVAL este numeric numeric, altfel folosim val default de 5 sec

STATE_FILE = Path(BACKUP_DIR) / "backup_state.json"
        # Fisier de stare pentru a retine ultimul hash/mtime/size

#Logging setup
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S%z",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("backup")

#Utilitare
def safe_mkdir(p: Path) -> None:
    try:
        p.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        log.error("Nu pot crea directorul '%s': %s", p, e)
        # nu ridicam mai departe; scriptul nu trebuie sa moara

def load_state() -> dict:
    try:
        if STATE_FILE.exists():
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        log.warning("Nu pot citi fisierul de stare '%s': %s (continui cu stare goala)", STATE_FILE, e)
    return {}

def save_state(state: dict) -> None:
    try:
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(STATE_FILE)
    except Exception as e:
        log.warning("Nu pot salva fisierul de stare '%s': %s", STATE_FILE, e)

def sha256_file(path: Path) -> str:
    """Hash pe bucati, pentru fisiere mari; intoarce hex digest sau '' daca esueaza."""
    try:
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception as e:
        log.warning("Nu pot calcula hash pentru '%s': %s", path, e)
        return ""

def utc_stamp_for_filename(dt: datetime) -> str:
    """Ex: 2025-11-06T13-22-09Z — pentru nume de fisiere."""
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")

def human_readable_size(size, decimal_places=2):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024:
            return f"{size:.{decimal_places}f} {unit}"
        size /= 1024

# Bucata principala
RUNNING = True
def handle_sig(signum, frame):
    global RUNNING
    log.info("Primit semnal %s — opresc bucla de backup...", signum)
    RUNNING = False

signal.signal(signal.SIGINT, handle_sig)
signal.signal(signal.SIGTERM, handle_sig)
        #tot nu tratam SIGKILL(kill -9)

def main():
    src = Path(SOURCE_FILE).resolve()
    backup_dir = Path(BACKUP_DIR).resolve()

    safe_mkdir(backup_dir)
    state = load_state()

    log.info("Pornesc backup-ul (interval=%ss, sursa=%s, dest=%s)",
             BACKUP_INTERVAL_S, str(src), str(backup_dir))

    last_hash = state.get("last_hash", "")
    last_size = state.get("last_size", -1)
    last_mtime = state.get("last_mtime", -1)

    while RUNNING:
        try:
            if not src.exists():
                log.warning("Fisierul sursa nu exista inca: %s (reverific peste %ss)", src, BACKUP_INTERVAL_S)
                time.sleep(BACKUP_INTERVAL_S)
                continue

            try:
                stat = src.stat()
                size = stat.st_size
                mtime = int(stat.st_mtime)
            except Exception as e:
                log.warning("Nu pot obtine metadata pentru '%s': %s", src, e)
                time.sleep(BACKUP_INTERVAL_S)
                continue

            changed = (size != last_size) or (mtime != last_mtime) # Analizam daca s-a modificat log-ul
            current_hash = ""

            if changed:
                # Verificam si hash-ul ca sa evitam backup-uri false pozitive (ex: mtime schimbat dar continut identic)
                current_hash = sha256_file(src)
                if current_hash and current_hash == last_hash:
                    changed = False  # continut identic, nu facem backup

            if changed:
                # Generam denumirea backup-ului
                base = src.name  # ex: VM-state.log
                ts = utc_stamp_for_filename(datetime.now(timezone.utc))
                backup_name = f"{base}__{ts}"
                dest = Path(backup_dir).joinpath(backup_name)

                try:
                    shutil.copy2(src, dest)
                    size = os.path.getsize(dest)
                    size_hr = human_readable_size(size)
                    log.info("Backup efectuat: %s (%s)", dest, size_hr)
                    # actualizam starea
                    last_size = size
                    last_mtime = mtime
                    last_hash = current_hash or sha256_file(src)  # ne asiguram ca avem hash
                    state = {
                        "last_size": last_size,
                        "last_mtime": last_mtime,
                        "last_hash": last_hash,
                        "source": str(src),
                        "backup_dir": str(backup_dir),
                        "last_backup_file": str(dest),
                        "last_backup_utc": ts,
                    }
                    save_state(state)
                except Exception as e:
                    log.error("Eroare la copierea backup-ului in '%s': %s", dest, e)
            else:
                log.debug("Nicio modificare la sursa — nu fac backup.")

        except Exception as e:
            # Orice exceptie neprevazuta este logata, dar NU termina procesul
            log.error("Eroare neasteptata in bucla: %s", e)

        # Asteptam pana la urmatorul backup
        try:
            time.sleep(BACKUP_INTERVAL_S)
        except Exception:
            # in cazuri rare (ex: sistemul schimba timpul), ignoram
            pass

    log.info("Backup oprit. Ultima stare: size=%s mtime=%s hash=%s",
             last_size, last_mtime, last_hash if last_hash else "")

if __name__ == "__main__": 
    # la rularea scripului, Python seteaza __name__(denumirea scriptului) la "__main__" (coincidenta)
    # Practic ne aparam de rularea automata a scriptului ( in caz de import in alt script)
    try:
        main()
    except Exception as e:
        # Ultima plasa de siguranta — nu iesim cu eroare, doar logam.
        logging.getLogger("backup").error("Eroare fatala neasteptata: %s", e) #log = logging.getLogger("backup")
        # exit 0 ca sa respecte cerinta "sa nu se termine cu eroare"
        sys.exit(0)
