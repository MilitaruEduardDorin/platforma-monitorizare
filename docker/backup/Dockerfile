# Dockerfile pentru imaginea scriptului de backup Python.

FROM python:3.12-slim

# Nu scrie .pyc si scoate buffering la stdout/stderr (utile la loguri în container). Setarile de Python trebuie sa fie active inainte de rularea backup.py
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copiem scriptul (pastreaza structura repo-ului tau)
# Contextul de build va fi /home/eu/Proiect_final, deci calea relativa e corecta
COPY scripts/backup_VM_ubuntu.py /app/backup_VM_ubuntu.py

# Cream directoare implicite pentru volume (vor fi suprascrise de -v în run/compose)
RUN mkdir -p /logs /backup

# ruleaza ca user neprivilegiat
RUN addgroup --system app && adduser --system --ingroup app app \
 && chown -R app:app /app /logs /backup
USER app

# Valorile implicite ale variabilei din scriptul de backup. Doua layer-e de ENV pt lizibilitate
ENV SOURCE_FILE=/logs/VM-state.log \
    BACKUP_DIR=/backup \
    BACKUP_INTERVAL=5

# Procesul principal
CMD ["python", "/app/backup_VM_ubuntu.py"]
