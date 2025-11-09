# Dockerfile pentru imaginea scriptului de monitorizare bash.

FROM ubuntu:24.04

# Instalare pachete necesare (top/free/ps (procps), ip (iproute2), awk, coreutils), fara dependente,si curatam cache-ul apt (imagine cu dimensiune mica)
RUN apt-get update && apt-get install -y --no-install-recommends \
    procps iproute2 gawk coreutils \
  && rm -rf /var/lib/apt/lists/*

# Director de lucru
WORKDIR /app

# Copiem scriptul din repo în container 
COPY scripts/monitorizare_VM_ubuntu.sh /app/monitorizare_VM_ubuntu.sh
RUN chmod +x /app/monitorizare_VM_ubuntu.sh

# Variabile implicite (se pot suprascrie la rulare)
ENV INTERVAL_RULARE=5 \
    TOP_PROCESE=10 \
    LOG_FILE=/logs/VM-state.log \
    LC_ALL=C

# Directorul de log (montat ca volum din VM)
RUN mkdir -p /logs

# Rulam scriptul de monitorizare in container
CMD ["/app/monitorizare_VM_ubuntu.sh"]
