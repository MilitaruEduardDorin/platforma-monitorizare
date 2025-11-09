#!/usr/bin/env bash
    #Pentru ca scriptul sa ruleze cu interpretorul bash

#monitorizare_VM_ubuntu.sh — Script bash care monitorizeaza sistem.
    #Noteza starea VM-ului ubuntu în VM-state.log, si il suprascrie la fiecare rulare (implicit o data la 5 secunde)

set -u          #pentru a evita rularea cu variabile nedefinite. util pt rularile cu valori custom (ex. typo nume var, nesetare val var)
set -o pipefail #daca o comanda dintr-un pipeline are eroare, atunci tot pipeline-ul va esua (ex. cmd1|cmd2_err|cmd3)

# Stabilire variabile de mediu

: "${INTERVAL_RULARE:=5}"              # interval de generare a log-ului\rulare a scriptului in secunde
: "${LOG_FILE:=VM-state.log}"    # denumirea fisierului log
: "${TOP_PROCESE:=10}"                        # pentru a afisa doar primele 10 procese ca si consum de CPU

[[ "$INTERVAL_RULARE" =~ ^[0-9]+$ && "$INTERVAL_RULARE" -gt 0 ]] || { echo "INTERVAL_RULARE trebuie să fie un număr întreg > 0" >&2; exit 1; }
    #verificam ca $INTERVAL_RULARE e nr intreg si mai mare decat 0
[[ "$TOP_PROCESE" =~ ^[0-9]+$ && "$TOP_PROCESE" -gt 0 ]] || { echo "TOP_PROCESE trebuie să fie un număr întreg > 0" >&2; exit 2; }
    #verificam ca $TOP_PROCESE e nr intreg si mai mare decat 0

    #Verificare variaba $LOG_FILE, daca exista directorul, si daca putem scrie in director
out_dir="$(dirname -- "$LOG_FILE")"
if [[ ! -d "$out_dir" ]]; then
  echo "Directorul '$out_dir' nu există, îl creez..."
  mkdir -p -- "$out_dir" || { echo "Nu se poate crea '$out_dir'"; exit 3; }
fi
[[ -w "$out_dir" ]] || { echo "Nu se poate scrie in directorul '$out_dir'"; exit 4; }

# Pastram localizare de tip C (in engleza) in tot scriptul pentru parsare consistentă (ex: top/free/awk)
export LC_ALL=C

# Afișează un mesaj la Ctrl+C, sau kill 'bland', și iesim din script fara eroare
trap 'echo " --> Se oprește monitorizarea..."; exit 0' INT TERM

#Functie pentru colectatrea datelor pt LOG
collect_LOG_data() {
  #Data si ora
  getdate_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  getdate_local="$(date +"%Y-%m-%d %H:%M:%S %Z")"

  # Date despre host
  hostname="$(hostname)" #numele Vm-ului
  os="$(source /etc/os-release && echo "${PRETTY_NAME:-Fara date}")" #versiune OS
  kernel="$(uname -rm)" # versiune kernel si arhitectura
  uptime_host="$(uptime -p 2>/dev/null || true)" #de cand e pornit VM-ul
  load_avg="$(cut -d ' ' -f1-3 /proc/loadavg 2>/dev/null || true)" #media proceselor din coada CPU la interval de 1, 5 si 15 minute

  # date despre CPU
  cpu_line="$(top -bn1 | awk -F',' '/Cpu\(s\)/{print $0; exit}')"
    # Extragem linia CPU din top, in format text pentru o singura iteratie
  cpu_user_usage="$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if ($i ~ /us/) print $i}' | awk '{print $1}')"
  cpu_sys_usage="$(echo "$cpu_line"  | awk -F',' '{for(i=1;i<=NF;i++) if ($i ~ /sy/) print $i}' | awk '{print $1}')"
  cpu_idle_usage="$(echo "$cpu_line" | awk -F',' '{for(i=1;i<=NF;i++) if ($i ~ /id/) print $i}' | awk '{print $1}')"
    #Vedem cat din CPU e utilizat de user, kernel, sau cat timp e idle

  # Memorie
  mem_line="$(free -h)" #sumarul memoriei
  mem_total="$(echo "$mem_line" | awk '/Mem:/ {print $2}')"
  mem_used="$(echo "$mem_line"  | awk '/Mem:/ {print $3}')"
  mem_free="$(echo "$mem_line"  | awk '/Mem:/ {print $4}')"
  mem_shared="$(echo "$mem_line"  | awk '/Mem:/ {print $5}')"
  mem_buff_cache="$(echo "$mem_line" | awk '/Mem:/ {print $6}')"
  mem_available="$(echo "$mem_line" | awk '/Mem:/ {print $7}')"

  # Procese
  proc_total_count="$(ps -A --no-headers | wc -l | awk '{print $1}')"
  top_procs_cpu="$(ps -eo user,pid,comm,%cpu,%mem --sort=-%cpu \
                | head -n $((TOP_PROCESE + 1)) \
                | awk 'NR==1{printf " %-20s %-7s %-20s %6s %6s\n",$1,$2,$3,$4,$5; next} NR>1{printf " %-20s %-7s %-20s %6s %6s\n",$1,$2,$3,$4,$5}' )"
  top_procs_mem="$(ps -eo user,pid,comm,%cpu,%mem --sort=-%mem \
                | head -n $((TOP_PROCESE + 1)) \
                | awk 'NR==1{printf " %-20s %-7s %-20s %6s %6s\n",$1,$2,$3,$4,$5; next} NR>1{printf " %-20s %-7s %-20s %6s %6s\n",$1,$2,$3,$4,$5}' )"
  
  # Disk
  disks="$(df -h --output=source,fstype,size,used,avail,pcent,target \
            | awk '{printf " %-18s %-6s %6s %6s %6s %6s  %s\n",$1,$2,$3,$4,$5,$6,$7}')"

  # Rețea
  ip_info="$(ip -brief addr 2>/dev/null | awk '{if (NF>=3) {ip_all=substr($0, index($0,$3));} else {ip_all ="-";}
                                                printf " %-10s %-6s %s\n",$1,$2,ip_all}')"
  routes="$(ip route show default 2>/dev/null)"

  # Scriere detalii LOG
  cat > "$LOG_FILE" <<EOF
============================================================
  STARE SISTEM (monitorizare) — $getdate_local (local) | $getdate_UTC (UTC)
============================================================

[Host]
  Hostname       : $hostname
  OS             : $os
  Kernel         : $kernel
  Uptime         : ${uptime_host:-Fara date}
  Load Average   : ${load_avg:-Fara date}

[CPU]
  User           : ${cpu_user_usage:-Fara date}
  System         : ${cpu_sys_usage:-Fara date}
  Idle           : ${cpu_idle_usage:-Fara date}

[Memorie]
  Total          : ${mem_total:-Fara date}
  Utilizată      : ${mem_used:-Fara date}
  Liberă         : ${mem_free:-Fara date}
  Buff/Cache     : ${mem_buff_cache:-Fara date}
  Shared         : ${mem_shared:-Fara date}
  Disponibilă    : ${mem_available:-Fara date}

[Procese]
  Număr procese  : ${proc_total_count:-Fara date}
  Top ${TOP_PROCESE} după CPU:
${top_procs_cpu:-Fara date}

  Top ${TOP_PROCESE} după MEM:
${top_procs_mem:-Fara date}

[Disk Usage]
${disks:-Fara date}

[Rețea]
  Interfețe:
${ip_info:-Fara date}

  Rute implicite:
${routes:-Fara date}

(Note) Acest fișier este suprascris la fiecare ciclu (interval: ${INTERVAL_RULARE}s).
EOF
}

echo "Pornesc monitorizarea (interval=${INTERVAL_RULARE}s, fișier=${LOG_FILE}, numar procese=${TOP_PROCESE}). Ctrl+C pentru a opri."
while true; do
  # Colectăm și suprascriem fișierul
  if ! collect_LOG_data; then
    echo "A apărut o eroare în timpul colectării informațiilor." >&2
  fi
  sleep "${INTERVAL_RULARE}"
done
