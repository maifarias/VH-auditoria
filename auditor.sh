#!/bin/bash

# Archivo donde se guarda el PID del demonio
PID_FILE="./audit.pid"

usage() {
    echo "Uso: $0 -r <repo> -c <config> -l <log> [-k]"
    echo "  -r | --repo          Ruta del repositorio a auditar"
    echo "  -c | --configuracion Archivo de configuración de patrones"
    echo "  -l | --log           Archivo de log"
    echo "  -k | --kill          Detiene el demonio si está corriendo"
    exit 1
}

# Parseo de parametros
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo) REPO="$2"; shift 2 ;;
        -c|--configuracion) CONFIG="$2"; shift 2 ;;
        -l|--log) LOG="$2"; shift 2 ;;
        -k|--kill) KILL=1; shift ;;
        *) usage ;;
    esac
done

# Si se utiliza la opción -k, se intenta detener el demonio
if [[ "$KILL" == "1" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID"
            rm -f "$PID_FILE"
            echo "Demonio detenido (PID $PID)"
            exit 0
        else
            echo "No hay demonio en ejecución con PID $PID"
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        echo "No existe archivo $PID_FILE, no hay demonio que detener"
        exit 1
    fi
fi

# Validaciones minimas
if [[ -z "$REPO" || -z "$CONFIG" || -z "$LOG" ]]; then
    usage
fi

# Comprobacion de repo git válido
if ! git -C "$REPO" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "'$REPO' no es un repositorio Git válido"
    exit 1
fi

# Detectar la rama actual
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
echo "Monitoreando la rama: $BRANCH"

# Iniciar el demonio en segundo plano
(
    echo "Iniciando demonio..."

    # Tomo el commit actual como punto de partida
    last_commit=$(git -C "$REPO" rev-parse HEAD)

    while true; do
        # Commit actual de la rama activa local
        new_commit=$(git -C "$REPO" rev-parse HEAD)

        if [ "$new_commit" != "$last_commit" ]; then
            echo "Nuevo commit detectado: $new_commit"

            # Archivos modificados entre commits
            archivos=$(git -C "$REPO" diff --name-only "$last_commit" "$new_commit")
            for archivo in $archivos; do
                while read -r patron; do
                    if grep -q "$patron" "$REPO/$archivo"; then
                        mensaje="$(date '+%Y-%m-%d %H:%M:%S') Alerta: Patrón '$patron' encontrado en '$archivo'"
                        echo "$mensaje" | tee -a "$LOG"
                    fi
                done < "$CONFIG"
            done

            last_commit=$new_commit
        fi

        sleep 10
    done
) &

# Guarda el PID del demonio
echo $! > "$PID_FILE"
echo "Demonio corriendo en segundo plano con PID $(cat "$PID_FILE")"

