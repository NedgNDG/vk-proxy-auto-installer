#!/bin/bash

# === НАСТРОЙКИ ===
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
CONFIG_DIR="/etc/vk-proxy"
CONFIG_FILE="$CONFIG_DIR/vk-proxy.conf"
CLIENTS_DIR="/root/vpn-clients"

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (команда: sudo bash)"
  exit 1
fi

mkdir -p "$CONFIG_DIR" "$CLIENTS_DIR"

# === ФУНКЦИИ КОНФИГУРАЦИИ ===
get_conf() {
    if [ -f "$CONFIG_FILE" ]; then
        grep "^$1=" "$CONFIG_FILE" | cut -d'=' -f2-
    fi
}

set_conf() {
    if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi
    if grep -q "^$1=" "$CONFIG_FILE"; then
        sed -i "s|^$1=.*|$1=$2|" "$CONFIG_FILE"
    else
        echo "$1=$2" >> "$CONFIG_FILE"
    fi
}

# Миграция со старых файлов и путей на новые (настроек скрипта)
migrate_configs() {
    if [ -f /root/.vk-proxy.conf ]; then
        mv /root/.vk-proxy.conf "$CONFIG_FILE"
    fi
    
    if [ -f /root/.vk-proxy-version ]; then
        set_conf "VERSION" "$(cat /root/.vk-proxy-version)"
        set_conf "PROXY_PORT" "$(cat /root/.vk-proxy-port 2>/dev/null || echo 56000)"
        set_conf "TARGET_PORT" "$(cat /root/.vk-proxy-target-port 2>/dev/null || echo 51820)"
        set_conf "PROXY_REPO" "$(cat /root/.vk-proxy-repo 2>/dev/null || echo cacggghp/vk-turn-proxy)"
        set_conf "CORE_TYPE" "$(cat /root/.vk-proxy-core-type 2>/dev/null || echo go)"
        
        if [[ "$(cat /root/.vk-proxy-vless 2>/dev/null)" == "1" ]]; then set_conf "VLESS_MODE" "vless"; else set_conf "VLESS_MODE" "off"; fi
        if [[ "$(cat /root/.vk-proxy-dc-mode 2>/dev/null)" == "1" ]]; then set_conf "DC_MODE" "1"; else set_conf "DC_MODE" "0"; fi
        
        set_conf "JAZZ_ROOM" "$(cat /root/.vk-proxy-jazz-room 2>/dev/null)"
        set_conf "YANDEX_LINK" "$(cat /root/.vk-proxy-yandex-link 2>/dev/null)"
        set_conf "CUSTOM_ARGS" "$(cat /root/.vk-proxy-custom-args 2>/dev/null)"
        
        # Удаляем старые файлы
        rm -f /root/.vk-proxy-version /root/.vk-proxy-port /root/.vk-proxy-target-port /root/.vk-proxy-repo \
              /root/.vk-proxy-core-type /root/.vk-proxy-vless /root/.vk-proxy-dc-mode /root/.vk-proxy-jazz-room \
              /root/.vk-proxy-yandex-link /root/.vk-proxy-custom-args /root/.vk-proxy-yandex-dc
    fi
}
migrate_configs

# === ФУНКЦИЯ СОЗДАНИЯ ПАНЕЛИ ===
create_panel() {
cat << 'EOF' > /usr/local/bin/vk-panel
#!/bin/bash
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"
CONFIG_DIR="/etc/vk-proxy"
CONFIG_FILE="$CONFIG_DIR/vk-proxy.conf"
CLIENTS_DIR="/root/vpn-clients"

mkdir -p "$CONFIG_DIR" "$CLIENTS_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

PUBLIC_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 https://api.ipify.org)

get_conf() { if [ -f "$CONFIG_FILE" ]; then grep "^$1=" "$CONFIG_FILE" | cut -d'=' -f2-; fi }
set_conf() { if [ ! -f "$CONFIG_FILE" ]; then touch "$CONFIG_FILE"; fi; if grep -q "^$1=" "$CONFIG_FILE"; then sed -i "s|^$1=.*|$1=$2|" "$CONFIG_FILE"; else echo "$1=$2" >> "$CONFIG_FILE"; fi }

CURRENT_VERSION=$(get_conf "VERSION")
CURRENT_VERSION=${CURRENT_VERSION:-"Неизвестно"}
PROXY_PORT=$(get_conf "PROXY_PORT")
PROXY_PORT=${PROXY_PORT:-"56000"}
TARGET_PORT=$(get_conf "TARGET_PORT")
TARGET_PORT=${TARGET_PORT:-"51820"}
PROXY_REPO=$(get_conf "PROXY_REPO")
PROXY_REPO=${PROXY_REPO:-"cacggghp/vk-turn-proxy"}

# Миграция репозитория
if [[ "$PROXY_REPO" != *"/"* ]] && [[ "$PROXY_REPO" != "Прямая ссылка" ]]; then
    if [[ "$PROXY_REPO" == "Urtyom-Alyanov" ]]; then PROXY_REPO="Urtyom-Alyanov/turn-proxy"; else PROXY_REPO="${PROXY_REPO}/vk-turn-proxy"; fi
    set_conf "PROXY_REPO" "$PROXY_REPO"
fi
if [[ "$PROXY_REPO" == "alexmac6574/vk-turn-proxy" ]]; then PROXY_REPO="alxmcp/vk-turn-proxy"; set_conf "PROXY_REPO" "$PROXY_REPO"; fi

get_download_url() {
    local api_resp="$1"
    local arch="$2"
    local repo="$3"
    local url=""
    if [[ "$repo" == *"Urtyom-Alyanov"* ]]; then
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        url=$(echo "$api_resp" | jq -r '.assets[] | select(.name == "server-linux-'"${arch}"'") | .browser_download_url' | head -n 1)
    fi
    echo "$url"
}

get_exec_args() {
    local FINAL_ARGS=""
    local CUSTOM_ARGS=$(get_conf "CUSTOM_ARGS")
    
    if [[ -n "$CUSTOM_ARGS" ]]; then
        FINAL_ARGS="$CUSTOM_ARGS"
    else
        local VLESS_FLAG=""
        local DC_FLAG=""
        local WRAP_FLAG=""
        
        local VLESS_MODE=$(get_conf "VLESS_MODE")
        if [[ "$VLESS_MODE" == "vless" ]]; then VLESS_FLAG=" -vless"
        elif [[ "$VLESS_MODE" == "vless-bond" ]]; then VLESS_FLAG=" -vless-bond"
        fi
        
        if [[ "$(get_conf "DC_MODE")" == "1" ]]; then
            local JAZZ_ROOM=$(get_conf "JAZZ_ROOM")
            local LINK=$(get_conf "YANDEX_LINK")
            if [[ -n "$JAZZ_ROOM" ]]; then DC_FLAG=" -jazz-room $JAZZ_ROOM -dc"
            elif [[ -n "$LINK" ]]; then DC_FLAG=" -yandex-link $LINK -dc"
            fi
        fi

        if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
            WRAP_FLAG=" -wrap"
            local WRAP_KEY=$(get_conf "WRAP_KEY")
            if [[ -n "$WRAP_KEY" ]]; then
                WRAP_FLAG="$WRAP_FLAG -wrap-key $WRAP_KEY"
            fi
        fi

        local CORE_TYPE=$(get_conf "CORE_TYPE")
        CORE_TYPE=${CORE_TYPE:-"go"}

        if [[ "$CORE_TYPE" == "rust" ]]; then
            FINAL_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000$DC_FLAG$VLESS_FLAG$WRAP_FLAG"
        else
            FINAL_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$DC_FLAG$VLESS_FLAG$WRAP_FLAG"
        fi
    fi
    echo "$FINAL_ARGS"
}

apply_and_restart_service() {
    local EXEC_ARGS=$(get_exec_args)
cat <<EOF_SVC > /etc/systemd/system/vk-proxy.service
[Unit]
Description=VK TURN Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
LimitNOFILE=1048576
ExecStart=/root/server-linux-$SYS_ARCH $EXEC_ARGS
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF_SVC
    systemctl daemon-reload
    if systemctl is-active --quiet vk-proxy; then systemctl restart vk-proxy; fi
}

check_bbr_status() {
    if command -v sysctl &> /dev/null; then
        local bbr_status=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        if [[ "$bbr_status" == "bbr" ]]; then
            echo -e "${GREEN}Включен${NC}"
        else
            echo -e "${RED}Выключен${NC}"
        fi
    else
        echo -e "${YELLOW}Неизвестно${NC}"
    fi
}

while true; do
    clear
    
    TARGET_SERVICE="Введен вручную / Неизвестен"
    shopt -s nullglob
    for conf in /etc/hysteria/*.yaml /etc/hysteria/*.json "$CLIENTS_DIR"/*.yaml "$CLIENTS_DIR"/*.json; do
        port=$(grep -i -oP -m 1 '^listen:\s*(?:.*:)?\K\d+' "$conf" 2>/dev/null)
        if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="Hysteria2"; break; fi
    done
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf "$CLIENTS_DIR"/*.conf; do
            port=$(grep -oP -m 1 'ListenPort\s*=\s*\K\d+' "$conf" 2>/dev/null)
            if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="AmneziaWG"; break; fi
        done
    fi
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/wireguard/*.conf "$CLIENTS_DIR"/*.conf; do
            port=$(grep -oP -m 1 'ListenPort\s*=\s*\K\d+' "$conf" 2>/dev/null)
            if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="WireGuard"; break; fi
        done
    fi
    shopt -u nullglob

    if systemctl is-active --quiet vk-proxy; then PROXY_STATE="${GREEN}Активен${NC}"; else PROXY_STATE="${RED}Остановлен${NC}"; fi
    
    VLESS_MODE=$(get_conf "VLESS_MODE")
    if [[ "$VLESS_MODE" == "vless" ]]; then VLESS_TEXT="${GREEN}Включен (-vless)${NC}"
    elif [[ "$VLESS_MODE" == "vless-bond" ]]; then VLESS_TEXT="${GREEN}Включен (-vless-bond)${NC}"
    else VLESS_TEXT="${RED}Выключен${NC}"; fi

    if [[ "$(get_conf "DC_MODE")" == "1" ]]; then DC_TEXT="${GREEN}Включен${NC}"; else DC_TEXT="${RED}Выключен${NC}"; fi
    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then WRAP_TEXT="${GREEN}Включен${NC}"; else WRAP_TEXT="${RED}Выключен${NC}"; fi

    if [[ -n "$(get_conf "CUSTOM_ARGS")" ]]; then MODE_TEXT="${YELLOW}Кастомные аргументы (Raw)${NC}"
    else MODE_TEXT="${GREEN}Автоматический${NC}"; fi
    
    BBR_TEXT=$(check_bbr_status)

	echo "========================================================================="
    echo -e "${CYAN}                       VK TURN Proxy Manager v2.0                        ${NC}"
    echo "========================================================================="
    echo -e " 🟢 Статус:      ${PROXY_STATE}"
    echo -e " 📦 Версия:      ${YELLOW}${CURRENT_VERSION}${NC} (Ядро: ${CYAN}${PROXY_REPO}${NC})"
    echo -e " ⚙️  Режим:       ${MODE_TEXT}"
    echo -e " 🛡️  VLESS:       ${VLESS_TEXT}  |  📞 DataChannel: ${DC_TEXT}"
    echo -e " ☁️  WRAP:        ${WRAP_TEXT}  |  🚀 TCP BBR: ${BBR_TEXT}"
    echo "-------------------------------------------------------------------------"
    echo -e " 🌐 Внешний:     ${PUBLIC_IP}:${PROXY_PORT}"
    echo -e " 🎯 Назначение:  127.0.0.1:${TARGET_PORT} [${YELLOW}${TARGET_SERVICE}${NC}]"
    echo -e " 📁 Директория клиентов: ${YELLOW}${CLIENTS_DIR}${NC}"
    echo "========================================================================="
    echo -e "${YELLOW}--- Управление Proxy ---${NC}"
    echo "  1. 🟢 Запустить прокси"
    echo "  2. 🔴 Остановить прокси"
    echo "  3. 🔄 Перезапустить"
    echo "  4. 📥 Обновить ядро"
    echo "  5. 🔀 Сменить реализацию ядра"
    echo "  6. 🗑️ Полностью удалить прокси"
    echo ""
    echo -e "${YELLOW}--- Настройки ---${NC}"
    echo "  7. 🔌 Изменить порты (Внешний / Локальный)"
    echo "  8. 🛡️ Настройка VLESS (-vless / -vless-bond)"
    echo "  9. 📞 Включить/Выключить режим 'DataChannel (SaluteJazz / Yandex)'"
    echo " 10. ☁️ Настройка WRAP (Обфускация / Управление ключом)"
    echo " 11. ✍️ Задать кастомные аргументы запуска (Raw command)"
    echo ""
    echo -e "${YELLOW}--- VPN и Клиенты ---${NC}"
    echo " 12. ➕ Установка/Управление VPN (WG / AmneziaWG / Hysteria2)"
    echo " 13. 📱 Показать QR-код существующего клиента"
    echo ""
    echo -e "${YELLOW}--- Система ---${NC}"
    echo " 14. 🚀 Включить TCP BBR (Оптимизация скорости сети)"
    echo " 15. 💾 Создать Backup (Резервная копия настроек и клиентов)"
    echo " 16. 📊 Посмотреть логи"
    echo " 17. ⚙️ Обновить панель"
    echo "  0. ❌ Выйти"
    echo "========================================================================="
    read -p "Выбери действие: " choice

    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"

    case $choice in
        1) systemctl start vk-proxy; echo -e "${GREEN}Запущено!${NC}"; sleep 1 ;;
        2) systemctl stop vk-proxy; echo -e "${RED}Остановлено!${NC}"; sleep 1 ;;
        3) if systemctl restart vk-proxy; then echo -e "${GREEN}Успешно перезапущено!${NC}"; else echo -e "${RED}Ошибка перезапуска! Проверьте логи.${NC}"; fi; sleep 2 ;;
        4)
            if [[ "$PROXY_REPO" == "Прямая ссылка" || "$PROXY_REPO" == "Custom_Direct_Link" ]]; then
                echo -e "${YELLOW}Ядро установлено по прямой ссылке. Автоматическое обновление через API недоступно.${NC}"
                read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi
            
            echo "Проверка обновлений через GitHub API ($PROXY_REPO)..."
            API_RESP=$(curl -s --connect-timeout 10 "$API_URL")
            LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
            
            if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
                echo -e "${RED}Ошибка API GitHub (возможно исчерпан лимит). Попробуй позже.${NC}"; read -n 1 -s -r -p "Нажми любую клавишу..."; continue
            fi

            if [[ "$LATEST_TAG" == "$CURRENT_VERSION" ]]; then
                echo -e "${GREEN}У вас уже установлена актуальная версия ($CURRENT_VERSION)!${NC}"
            else
                echo -e "Доступна новая версия: ${YELLOW}$LATEST_TAG${NC} (текущая: $CURRENT_VERSION)"
                read -p "Хотите обновить? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$PROXY_REPO")
                    if [[ "$DOWNLOAD_URL" != "null" && -n "$DOWNLOAD_URL" ]]; then
                        echo "Скачивание обновления..."
                        if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            apply_and_restart_service
                            set_conf "VERSION" "$LATEST_TAG"
                            CURRENT_VERSION=$LATEST_TAG
                            echo -e "${GREEN}Успешно обновлено до $LATEST_TAG!${NC}"
                        else
                            echo -e "${RED}Ошибка скачивания файла обновления.${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        5)
            echo -e "${YELLOW}ВНИМАНИЕ: При смене реализации клиенты могут перестать подключаться!${NC}"
            echo -e "Текущая реализация: ${CYAN}${PROXY_REPO}${NC}"
            echo "Доступные реализации:"
            echo -e "1) cacggghp/vk-turn-proxy (Оригинал)"
            echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
            echo -e "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust, только amd64/x86_64)"
            echo -e "4) Moroka8/vk-turn-proxy (Форк)"
            echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка Yandex / SaluteJazz\e[0m)"
            echo -e "6) samosvalishe/vk-turn-proxy (Форк)"
            echo -e "7) Сторонний репозиторий GitHub ИЛИ прямая ссылка"
            echo "0) Отмена"
            read -p "Выберите новую реализацию [1-7 или 0]: " repo_choice
            
            case "$repo_choice" in
                1) NEW_REPO="cacggghp/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                2) NEW_REPO="kiper292/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                3) NEW_REPO="Urtyom-Alyanov/turn-proxy"; NEW_CORE_TYPE="rust" ;;
                4) NEW_REPO="Moroka8/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                5) NEW_REPO="alxmcp/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                6) NEW_REPO="samosvalishe/vk-turn-proxy"; NEW_CORE_TYPE="go" ;;
                7)
                    read -p "Введи репозиторий (owner/repo) ИЛИ прямую ссылку: " custom_input
                    if [[ "$custom_input" =~ ^https?:// ]] && [[ ! "$custom_input" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
                        NEW_REPO="Custom_Direct_Link"
                        DOWNLOAD_URL="$custom_input"
                        LATEST_TAG="Custom"
                    else
                        NEW_REPO=$(echo "$custom_input" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
                        if [[ -z "$NEW_REPO" || "$NEW_REPO" != *"/"* || "$NEW_REPO" == "/" ]]; then echo -e "${RED}Неверный формат.${NC}"; sleep 1; continue; fi
                    fi
                    echo -e "\n${CYAN}Какой тип аргументов использовать?${NC}"
                    echo "1) Стандартные (Go)"
                    echo "2) Rust"
                    echo "3) Задать вручную (Raw command)"
                    read -p "Твой выбор [1-3]: " custom_core_type
                    if [[ "$custom_core_type" == "2" ]]; then NEW_CORE_TYPE="rust"
                    elif [[ "$custom_core_type" == "3" ]]; then NEW_CORE_TYPE="custom"
                    else NEW_CORE_TYPE="go"; fi
                    ;;
                0) continue ;;
                *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1; continue ;;
            esac
            
            if [[ "$NEW_REPO" == "$PROXY_REPO" ]]; then echo -e "${YELLOW}Эта реализация уже установлена!${NC}"; sleep 1; continue; fi
            
            read -p "Сменить ядро? [y/N]: " confirm_switch
            if [[ "$confirm_switch" =~ ^[Yy]$ ]]; then
                if [[ "$NEW_REPO" == "Custom_Direct_Link" ]]; then
                    echo "Скачивание по прямой ссылке..."
                    if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                        systemctl stop vk-proxy
                        mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                        chmod +x /root/server-linux-$SYS_ARCH
                        PROXY_REPO="Прямая ссылка"
                        set_conf "CORE_TYPE" "$NEW_CORE_TYPE"
                        if [[ "$NEW_CORE_TYPE" == "custom" ]]; then
                            read -p "Введи аргументы вручную: " manual_custom_args
                            set_conf "CUSTOM_ARGS" "$manual_custom_args"
                        else set_conf "CUSTOM_ARGS" ""; fi
                        apply_and_restart_service
                        set_conf "PROXY_REPO" "Прямая ссылка"
                        set_conf "VERSION" "Custom"
                        CURRENT_VERSION="Custom"
                        echo -e "${GREEN}Обновлено!${NC}"
                    fi
                else
                    NEW_API_URL="https://api.github.com/repos/${NEW_REPO}/releases/latest"
                    API_RESP=$(curl -s --connect-timeout 10 "$NEW_API_URL")
                    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
                    if [[ "$LATEST_TAG" != "null" && -n "$LATEST_TAG" ]]; then
                        DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$NEW_REPO")
                        if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            PROXY_REPO=$NEW_REPO
                            set_conf "CORE_TYPE" "$NEW_CORE_TYPE"
                            if [[ "$NEW_CORE_TYPE" == "custom" ]]; then
                                read -p "Введи аргументы вручную: " manual_custom_args
                                set_conf "CUSTOM_ARGS" "$manual_custom_args"
                            else set_conf "CUSTOM_ARGS" ""; fi
                            apply_and_restart_service
                            set_conf "PROXY_REPO" "$NEW_REPO"
                            set_conf "VERSION" "$LATEST_TAG"
                            CURRENT_VERSION=$LATEST_TAG
                            echo -e "${GREEN}Обновлено!${NC}"
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        6)
            echo -e "${RED}ВНИМАНИЕ: Это удалит службу, бинарник прокси и его настройки! VPN останутся нетронутыми.${NC}"
            read -p "Вы АБСОЛЮТНО уверены? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop vk-proxy; systemctl disable vk-proxy; rm -f /etc/systemd/system/vk-proxy.service; systemctl daemon-reload
                if command -v ufw &> /dev/null; then ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1; fi
                rm -f /root/server-linux-$SYS_ARCH /usr/local/bin/vk-panel
                rm -rf "$CONFIG_DIR"
                echo -e "${GREEN}Прокси удален.${NC}"; exit 0
            fi ;;
        7)
            echo -e "${CYAN}Изменение портов:${NC}"
            echo "1) Внешний порт прокси (сейчас: $PROXY_PORT)"
            echo "2) Локальный порт назначения (сейчас: $TARGET_PORT)"
            echo "0) Отмена"
            read -p "Что меняем? [1, 2 или 0]: " port_change_choice
            if [[ "$port_change_choice" == "1" ]]; then
                read -p "Введи новый порт (1-65535): " NEW_PROXY_PORT
                if [[ "$NEW_PROXY_PORT" =~ ^[0-9]+$ ]]; then
                    if command -v ufw &> /dev/null; then
                        ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1
                        ufw allow $NEW_PROXY_PORT/tcp >/dev/null 2>&1; ufw allow $NEW_PROXY_PORT/udp >/dev/null 2>&1
                    fi
                    set_conf "PROXY_PORT" "$NEW_PROXY_PORT"; PROXY_PORT="$NEW_PROXY_PORT"
                    echo -e "${GREEN}Изменено!${NC}"
                fi
            elif [[ "$port_change_choice" == "2" ]]; then
                echo "1) Ввести вручную"
                echo "2) Найти автоматически (WG/AmneziaWG/Hysteria2)"
                read -p "Выбор: " target_port_method
                if [[ "$target_port_method" == "1" ]]; then
                    read -p "Локальный порт: " NEW_TARGET_PORT
                elif [[ "$target_port_method" == "2" ]]; then
                    shopt -s nullglob
                    ALL_CONFS=(/etc/wireguard/*.conf /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf /etc/hysteria/*.yaml /etc/hysteria/*.json "$CLIENTS_DIR"/*.conf "$CLIENTS_DIR"/*.yaml "$CLIENTS_DIR"/*.json)
                    shopt -u nullglob
                    if [ ${#ALL_CONFS[@]} -gt 0 ]; then
                        for i in "${!ALL_CONFS[@]}"; do
                            port=$(grep -i -oP -m 1 '(ListenPort\s*=\s*|^listen:\s*(?:.*:)?)\K\d+' "${ALL_CONFS[$i]}")
                            echo "$((i+1)). ${ALL_CONFS[$i]} (Порт: ${port:-не найден})"
                        done
                        read -p "Номер конфигурации: " conf_choice
                        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#ALL_CONFS[@]} ]]; then
                            NEW_TARGET_PORT=$(grep -i -oP -m 1 '(ListenPort\s*=\s*|^listen:\s*(?:.*:)?)\K\d+' "${ALL_CONFS[$((conf_choice-1))]}")
                        fi
                    else
                        echo -e "${RED}Файлы конфигураций не найдены.${NC}"
                    fi
                    
                    if [[ -z "$NEW_TARGET_PORT" ]]; then
                        echo -e "${YELLOW}Не удалось определить порт из файла.${NC}"
                        read -p "Введи порт вручную: " NEW_TARGET_PORT
                    fi
                fi
                if [[ -n "$NEW_TARGET_PORT" ]]; then set_conf "TARGET_PORT" "$NEW_TARGET_PORT"; TARGET_PORT="$NEW_TARGET_PORT"; echo -e "${GREEN}Изменено!${NC}"; fi
            fi
            if [[ "$port_change_choice" == "1" || "$port_change_choice" == "2" ]]; then apply_and_restart_service; fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        8)
            echo -e "${CYAN}Настройка VLESS:${NC}"
            echo "1) Отключить флаги VLESS"
            echo "2) Включить стандартный режим (-vless)"
            echo "3) Включить режим Bond (-vless-bond)"
            read -p "Ваш выбор [1-3]: " vless_choice
            case "$vless_choice" in
                1) set_conf "VLESS_MODE" "off"; echo -e "${YELLOW}VLESS отключен.${NC}" ;;
                2) set_conf "VLESS_MODE" "vless"; echo -e "${GREEN}Включен флаг -vless.${NC}" ;;
                3) set_conf "VLESS_MODE" "vless-bond"; echo -e "${GREEN}Включен флаг -vless-bond.${NC}" ;;
            esac
            apply_and_restart_service; sleep 1 ;;
        9)
            if [[ "$(get_conf "DC_MODE")" == "1" ]]; then
                set_conf "DC_MODE" "0"; echo -e "${YELLOW}DataChannel отключен.${NC}"
            else
                echo -e "${CYAN}Настройка DataChannel${NC}"
                echo "1) SaluteJazz"
                echo "2) Яндекс Телемост"
                read -p "Сервис [1-2]: " dc_choice
                if [[ "$dc_choice" == "1" ]]; then
                    read -p "Комната (Enter для any): " input_room
                    set_conf "JAZZ_ROOM" "${input_room:-any}"; set_conf "YANDEX_LINK" ""
                    set_conf "DC_MODE" "1"; echo -e "${GREEN}SaluteJazz включен!${NC}"
                elif [[ "$dc_choice" == "2" ]]; then
                    read -p "Ссылка Yandex: " input_link
                    if [[ -n "$input_link" ]]; then set_conf "YANDEX_LINK" "$input_link"; set_conf "JAZZ_ROOM" ""; set_conf "DC_MODE" "1"; echo -e "${GREEN}Yandex включен!${NC}"; fi
                fi
            fi
            apply_and_restart_service; sleep 1 ;;
        10)
            echo -e "${CYAN}Настройки WRAP (Обфускация):${NC}"
            echo "1) Включить/Выключить WRAP-обфускацию (-wrap)"
            echo "2) Показать текущий WRAP ключ"
            echo "3) Задать новый WRAP ключ / Сгенерировать случайный"
            read -p "Выбор [1-3]: " wrap_choice
            case "$wrap_choice" in
                1)
                    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
                        set_conf "WRAP_ENABLED" "0"; echo -e "${YELLOW}WRAP отключен.${NC}"
                    else
                        set_conf "WRAP_ENABLED" "1"; echo -e "${GREEN}WRAP включен.${NC}"
                    fi
                    apply_and_restart_service
                    ;;
                2)
                    CURRENT_WRAP_KEY=$(get_conf "WRAP_KEY")
                    if [[ -n "$CURRENT_WRAP_KEY" ]]; then echo -e "Текущий ключ: ${YELLOW}$CURRENT_WRAP_KEY${NC}"; else echo -e "Ключ не задан (используется базовый/встроенный)"; fi
                    ;;
                3)
                    echo -e "Вы можете вставить свой 64-символьный hex ключ."
                    echo -e "Или введите ${CYAN}gen${NC}, чтобы сгенерировать случайный ключ."
                    read -p "Ввод (или Enter для сброса): " input_wrap_key
                    if [[ "$input_wrap_key" == "gen" ]]; then
                        NEW_KEY=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
                        set_conf "WRAP_KEY" "$NEW_KEY"
                        echo -e "${GREEN}Сгенерирован и сохранен новый ключ: $NEW_KEY${NC}"
                    else
                        set_conf "WRAP_KEY" "$input_wrap_key"
                        echo -e "${GREEN}Ключ обновлен!${NC}"
                    fi
                    apply_and_restart_service
                    ;;
            esac
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        11)
            echo -e "${CYAN}Кастомные аргументы (Raw command)${NC}"
            echo -e "Внимание: при задании кастомных аргументов порты/VLESS/WRAP из панели игнорируются."
            read -p "Введи аргументы (или Enter для сброса на авто): " input_custom
            set_conf "CUSTOM_ARGS" "$input_custom"
            if [[ -z "$input_custom" ]]; then echo -e "${GREEN}Сброшено на авто!${NC}"; else echo -e "${GREEN}Сохранено!${NC}"; fi
            apply_and_restart_service; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        12) 
            echo -e "${CYAN}Управление VPN:${NC}"
            echo "1) WireGuard"
            echo "2) AmneziaWG"
            echo "3) Hysteria2"
            read -p "Выбор: " vpn_manage_choice
            if [[ "$vpn_manage_choice" == "1" ]]; then
                if [ ! -f /root/wireguard-install.sh ]; then curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; chmod +x /root/wireguard-install.sh; fi
                bash /root/wireguard-install.sh
            elif [[ "$vpn_manage_choice" == "2" ]]; then
                if [ ! -f /root/amneziawg-install.sh ]; then curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; chmod +x /root/amneziawg-install.sh; fi
                bash /root/amneziawg-install.sh
            elif [[ "$vpn_manage_choice" == "3" ]]; then
                if [ ! -f /root/hysteria-install.sh ]; then curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; chmod +x /root/hysteria-install.sh; fi
                bash /root/hysteria-install.sh
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        13)
            CLIENT_CONFS=()
            while IFS= read -r file; do CLIENT_CONFS+=("$file"); done < <(find "$CLIENTS_DIR" -type f \( -name "*.conf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.txt" \) -print 2>/dev/null)
            if [ ${#CLIENT_CONFS[@]} -gt 0 ]; then
                echo -e "${CYAN}Доступные конфигурации в $CLIENTS_DIR:${NC}"
                for i in "${!CLIENT_CONFS[@]}"; do echo "$((i+1)). $(basename "${CLIENT_CONFS[$i]}")"; done
                read -p "Номер файла (или 0): " qr_choice
                if [[ "$qr_choice" -ge 1 && "$qr_choice" -le ${#CLIENT_CONFS[@]} ]]; then qrencode -t ansiutf8 < "${CLIENT_CONFS[$((qr_choice-1))]}"; fi
            else echo -e "${RED}Файлы конфигураций не найдены в $CLIENTS_DIR.${NC}"; fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        14)
            echo -e "${CYAN}Оптимизация сети (TCP BBR)${NC}"
            if command -v sysctl &> /dev/null; then
                CURRENT_BBR=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
                if [[ "$CURRENT_BBR" == "bbr" ]]; then
                    echo -e "${GREEN}TCP BBR уже включен и работает! Ваш сервер оптимизирован.${NC}"
                else
                    echo -e "Текущий алгоритм контроля перегрузки: ${YELLOW}${CURRENT_BBR:-неизвестно}${NC}"
                    read -p "Включить TCP BBR для ускорения сети? [y/N]: " enable_bbr
                    if [[ "$enable_bbr" =~ ^[Yy]$ ]]; then
                        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                        sysctl -p > /dev/null 2>&1
                        echo -e "${GREEN}TCP BBR успешно включен! Скорость передачи данных должна улучшиться.${NC}"
                    else
                        echo -e "${YELLOW}Действие отменено.${NC}"
                    fi
                fi
            else
                echo -e "${RED}Утилита sysctl не найдена в системе. Невозможно управлять BBR.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        15)
            echo -e "${CYAN}Создание резервной копии (Backup)${NC}"
            BACKUP_NAME="vk-proxy-backup-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
            BACKUP_PATH="/root/$BACKUP_NAME"
            echo "Архивация директорий конфигурации..."
            tar -czf "$BACKUP_PATH" "$CONFIG_DIR" "$CLIENTS_DIR" 2>/dev/null
            if [ -f "$BACKUP_PATH" ]; then
                echo -e "${GREEN}Резервная копия успешно создана!${NC}"
                echo -e "Путь к файлу: ${YELLOW}$BACKUP_PATH${NC}"
                echo "💡 Сохраните этот файл на свой компьютер (через FileZilla/SFTP), чтобы не потерять настройки при переустановке сервера."
            else
                echo -e "${RED}Ошибка: Не удалось создать архив.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        16) journalctl -u vk-proxy -n 20 --no-pager; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        17) bash <(curl -sfL --connect-timeout 10 "$INSTALLER_URL") --update-panel; echo -e "${GREEN}Обновлено!${NC}"; exit 0 ;;
        0) clear; exit 0 ;;
    esac
done
EOF
chmod +x /usr/local/bin/vk-panel
}

if [[ "$1" == "--update-panel" ]]; then echo "Обновление vk-panel..."; create_panel; exit 0; fi

clear
echo "==================================================="
echo "   Ультимативный Установщик VPN + vk-turn-proxy    "
echo "==================================================="
echo ""

echo "[1/10] Установка зависимостей (curl, wget, jq, ufw, qrencode)..."
if command -v apt-get &> /dev/null; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget jq ufw qrencode > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq epel-release > /dev/null 2>&1
    yum install -y ufw qrencode > /dev/null 2>&1
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

echo ""
echo "[2/10] Выбор реализации vk-turn-proxy..."
echo -e "1) cacggghp/vk-turn-proxy (Оригинал)"
echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
echo -e "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust)"
echo -e "4) Moroka8/vk-turn-proxy (Форк)"
echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка Yandex / SaluteJazz\e[0m)"
echo -e "6) samosvalishe/vk-turn-proxy (Форк)"
echo -e "7) Сторонний репозиторий GitHub ИЛИ прямая ссылка"
read -p "Твой выбор [1-7, Enter для 6]: " repo_choice

case "${repo_choice:-6}" in
  1) PROXY_REPO="cacggghp/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
  2) PROXY_REPO="kiper292/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
  3) PROXY_REPO="Urtyom-Alyanov/turn-proxy"; set_conf "CORE_TYPE" "rust" ;;
  4) PROXY_REPO="Moroka8/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
  5) PROXY_REPO="alxmcp/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
  6) PROXY_REPO="samosvalishe/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
  7)
    read -p "Введи репозиторий (owner/repo) ИЛИ прямую ссылку: " custom_input
    if [[ "$custom_input" =~ ^https?:// ]] && [[ ! "$custom_input" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
        PROXY_REPO="Прямая ссылка"
        DOWNLOAD_URL_DIRECT="$custom_input"
    else
        PROXY_REPO=$(echo "$custom_input" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
        if [[ -z "$PROXY_REPO" || "$PROXY_REPO" != *"/"* || "$PROXY_REPO" == "/" ]]; then PROXY_REPO="samosvalishe/vk-turn-proxy"; set_conf "CORE_TYPE" "go"; fi
    fi
    echo -e "\nКакой тип аргументов использовать?"
    echo "1) Стандартные (Go)"
    echo "2) Rust"
    echo "3) Задать вручную (Raw command)"
    read -p "Твой выбор [1-3]: " custom_core_type
    if [[ "$custom_core_type" == "2" ]]; then set_conf "CORE_TYPE" "rust"
    elif [[ "$custom_core_type" == "3" ]]; then set_conf "CORE_TYPE" "custom"
    else set_conf "CORE_TYPE" "go"; fi
    ;;
  *) PROXY_REPO="samosvalishe/vk-turn-proxy"; set_conf "CORE_TYPE" "go" ;;
esac
set_conf "PROXY_REPO" "$PROXY_REPO"

echo ""
echo "[3/10] Настройка внешнего порт прокси..."
DEFAULT_PROXY_PORT=56000
[[ "$(get_conf "CORE_TYPE")" == "rust" ]] && DEFAULT_PROXY_PORT=56040

while true; do
    read -p "Введи внешний порт (Enter для $DEFAULT_PROXY_PORT): " INPUT_PROXY_PORT
    INPUT_PROXY_PORT=${INPUT_PROXY_PORT:-$DEFAULT_PROXY_PORT}
    if [[ "$INPUT_PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PROXY_PORT" -ge 1 ] && [ "$INPUT_PROXY_PORT" -le 65535 ]; then
        set_conf "PROXY_PORT" "$INPUT_PROXY_PORT"
        PROXY_PORT=$INPUT_PROXY_PORT
        break
    else echo "⚠️ Некорректный порт."; fi
done

echo ""
echo "[4/10] Настройка VLESS..."
echo "1) Не использовать VLESS флаги"
echo "2) Включить стандартный VLESS (-vless)"
echo "3) Включить VLESS Bond (-vless-bond)"
read -p "Выбор [1-3, Enter для 1]: " vless_setup
if [[ "$vless_setup" == "3" ]]; then set_conf "VLESS_MODE" "vless-bond"
elif [[ "$vless_setup" == "2" ]]; then set_conf "VLESS_MODE" "vless"
else set_conf "VLESS_MODE" "off"; fi

echo ""
echo "[5/10] Настройка локального порта (цель для прокси)..."
echo "1) Установить WireGuard с нуля"
echo "2) Установить AmneziaWG с нуля"
echo "3) Установить Hysteria2 с нуля"
echo "4) Ввести порт вручную (если WG/AWG, Hysteria2, Xray или 3X-UI уже установлены)"
read -p "Выбор [1-4]: " port_setup_choice

TARGET_PORT=""
if [[ "$port_setup_choice" == "4" ]]; then
    read -p "Введи локальный порт (например, 51820 или 443): " manual_port
    TARGET_PORT=${manual_port:-51820}
elif [[ "$port_setup_choice" == "3" ]]; then
    shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json); shopt -u nullglob
    if [ ${#HYS_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации Hysteria2."
        read -p "Хочешь запустить установщик Hysteria2? (выбери N, если Hysteria2 уже настроен) [y/N]: " run_hys
        if [[ "$run_hys" =~ ^[Yy]$ ]]; then
            curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; bash /root/hysteria-install.sh
            shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json); shopt -u nullglob
        fi
    else
        curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; bash /root/hysteria-install.sh
        shopt -s nullglob; HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json); shopt -u nullglob
    fi
    
    if [ ${#HYS_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(grep -i -oP -m 1 '^listen:\s*(?:.*:)?\K\d+' "${HYS_CONFS[0]}")
        echo "Автоматически выбран конфиг: ${HYS_CONFS[0]}"
    elif [ ${#HYS_CONFS[@]} -gt 1 ]; then
        echo "Найдено несколько конфигураций:"
        for i in "${!HYS_CONFS[@]}"; do echo "$((i+1)). ${HYS_CONFS[$i]}"; done
        read -p "Выбери номер конфига для привязки прокси: " conf_choice
        conf_choice=${conf_choice:-1}
        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#HYS_CONFS[@]} ]]; then
            TARGET_PORT=$(grep -i -oP -m 1 '^listen:\s*(?:.*:)?\K\d+' "${HYS_CONFS[$((conf_choice-1))]}")
        fi
    fi
elif [[ "$port_setup_choice" == "2" ]]; then
    shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf); shopt -u nullglob
    if [ ${#AWG_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации AmneziaWG."
        read -p "Хочешь запустить установщик AmneziaWG? (выбери N, если AWG уже настроен) [y/N]: " run_awg
        if [[ "$run_awg" =~ ^[Yy]$ ]]; then
            curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; bash /root/amneziawg-install.sh
            shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf); shopt -u nullglob
        fi
    else
        curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; bash /root/amneziawg-install.sh
        shopt -s nullglob; AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf); shopt -u nullglob
    fi
    
    if [ ${#AWG_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${AWG_CONFS[0]}")
        echo "Автоматически выбран конфиг: ${AWG_CONFS[0]}"
    elif [ ${#AWG_CONFS[@]} -gt 1 ]; then
        echo "Найдено несколько конфигураций:"
        for i in "${!AWG_CONFS[@]}"; do echo "$((i+1)). ${AWG_CONFS[$i]}"; done
        read -p "Выбери номер конфига для привязки прокси: " conf_choice
        conf_choice=${conf_choice:-1}
        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#AWG_CONFS[@]} ]]; then
            TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${AWG_CONFS[$((conf_choice-1))]}")
        fi
    fi
else
    shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf); shopt -u nullglob
    if [ ${#WG_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации WireGuard."
        read -p "Хочешь запустить установщик WireGuard? (выбери N, если WG уже настроен) [y/N]: " run_wg
        if [[ "$run_wg" =~ ^[Yy]$ ]]; then
            curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; bash /root/wireguard-install.sh
            shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf); shopt -u nullglob
        fi
    else
        curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; bash /root/wireguard-install.sh
        shopt -s nullglob; WG_CONFS=(/etc/wireguard/*.conf); shopt -u nullglob
    fi
    
    if [ ${#WG_CONFS[@]} -eq 1 ]; then
        TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${WG_CONFS[0]}")
        echo "Автоматически выбран конфиг: ${WG_CONFS[0]}"
    elif [ ${#WG_CONFS[@]} -gt 1 ]; then
        echo "Найдено несколько конфигураций:"
        for i in "${!WG_CONFS[@]}"; do echo "$((i+1)). ${WG_CONFS[$i]}"; done
        read -p "Выбери номер конфига для привязки прокси: " conf_choice
        conf_choice=${conf_choice:-1}
        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#WG_CONFS[@]} ]]; then
            TARGET_PORT=$(grep -oP 'ListenPort\s*=\s*\K\d+' "${WG_CONFS[$((conf_choice-1))]}")
        fi
    fi
fi

if [[ -z "$TARGET_PORT" ]]; then
    echo -e "\033[0;33m⚠️ Не удалось автоматически определить порт из конфигураций.\033[0m"
    read -p "Введи целевой локальный порт вручную: " TARGET_PORT
fi
TARGET_PORT=${TARGET_PORT:-51820}
set_conf "TARGET_PORT" "$TARGET_PORT"

echo ""
echo "[6/10] Загрузка ядра ($SYS_ARCH)..."
if [[ "$PROXY_REPO" == "Прямая ссылка" ]]; then
    wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL_DIRECT"
    LATEST_TAG="Custom"
else
    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"
    API_RESP=$(curl -s --connect-timeout 10 "$API_URL")
    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")

    if [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "server-linux-'"${SYS_ARCH}"'") | .browser_download_url' | head -n 1)
    fi

    wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"
fi
chmod +x /root/server-linux-$SYS_ARCH
set_conf "VERSION" "$LATEST_TAG"

echo ""
echo "[7/10] Настройка WRAP (Обфускация)..."
echo "1) Пропустить (Не использовать WRAP)"
echo "2) Включить WRAP (использовать встроенный/базовый ключ)"
echo "3) Включить WRAP и сгенерировать случайный ключ (hex 64)"
echo "4) Включить WRAP и ввести свой ключ вручную"
read -p "Выбор [1-4, Enter для 1]: " wrap_setup_choice

case "$wrap_setup_choice" in
    2) 
        set_conf "WRAP_ENABLED" "1"
        echo "✅ WRAP включен с базовым ключом."
        ;;
    3) 
        set_conf "WRAP_ENABLED" "1"
        NEW_KEY=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
        set_conf "WRAP_KEY" "$NEW_KEY"
        echo "✅ Сгенерирован и сохранен новый ключ: $NEW_KEY"
        ;;
    4) 
        set_conf "WRAP_ENABLED" "1"
        read -p "Введи свой 64-символьный hex ключ: " input_wrap_key
        set_conf "WRAP_KEY" "$input_wrap_key"
        echo "✅ Ключ сохранен."
        ;;
    *) 
        set_conf "WRAP_ENABLED" "0" 
        echo "WRAP пропущен."
        ;;
esac

echo ""
echo "[8/10] Настройка кастомных аргументов (Raw command)..."
echo "Обычно скрипт генерирует их автоматически на базе портов, но ты можешь задать команду вручную (Raw mode)."
echo "Внимание: при задании кастомных аргументов настройки портов/VLESS/WRAP из панели игнорируются."
read -p "Хочешь прописать кастомные аргументы запуска? [y/N]: " custom_args_choice

if [[ "$custom_args_choice" =~ ^[Yy]$ ]]; then
    read -p "Введи аргументы: " input_custom
    set_conf "CUSTOM_ARGS" "$input_custom"
    echo "✅ Сохранено."
else
    set_conf "CUSTOM_ARGS" ""
    echo "Пропущено. Аргументы будут сгенерированы автоматически."
fi

echo ""
echo "[9/10] Настройка службы..."
systemctl stop vk-proxy 2>/dev/null || true

CUSTOM_ARGS=$(get_conf "CUSTOM_ARGS")
if [[ -n "$CUSTOM_ARGS" ]]; then
    EXEC_ARGS="$CUSTOM_ARGS"
else
    VLESS_FLAG=""
    VLESS_MODE=$(get_conf "VLESS_MODE")
    if [[ "$VLESS_MODE" == "vless" ]]; then VLESS_FLAG=" -vless"
    elif [[ "$VLESS_MODE" == "vless-bond" ]]; then VLESS_FLAG=" -vless-bond"
    fi

    WRAP_FLAG=""
    if [[ "$(get_conf "WRAP_ENABLED")" == "1" ]]; then
        WRAP_FLAG=" -wrap"
        WRAP_KEY=$(get_conf "WRAP_KEY")
        if [[ -n "$WRAP_KEY" ]]; then
            WRAP_FLAG="$WRAP_FLAG -wrap-key $WRAP_KEY"
        fi
    fi

    CORE_TYPE=$(get_conf "CORE_TYPE")
    if [[ "$CORE_TYPE" == "rust" ]]; then EXEC_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000$VLESS_FLAG$WRAP_FLAG"
    else EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$VLESS_FLAG$WRAP_FLAG"; fi
fi

cat <<EOF > /etc/systemd/system/vk-proxy.service
[Unit]
Description=VK TURN Proxy Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
LimitNOFILE=1048576
ExecStart=/root/server-linux-$SYS_ARCH $EXEC_ARGS
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vk-proxy > /dev/null 2>&1
systemctl start vk-proxy

if command -v ufw &> /dev/null; then ufw allow $PROXY_PORT/tcp > /dev/null 2>&1; ufw allow $PROXY_PORT/udp > /dev/null 2>&1; fi

echo ""
echo "[10/10] Создание панели (vk-panel)..."
create_panel

echo ""
echo "==================================================="
echo "✅ Установка полностью завершена!"
echo "Трафик прокси направляется на локальный порт: $TARGET_PORT"
echo "Внешний порт прокси: $PROXY_PORT"
echo "📁 Новые файлы клиентов будут сохраняться в: $CLIENTS_DIR"
echo "==================================================="
echo "⚠️  ВАЖНО ДЛЯ ОБЛАКОВ (Oracle, AWS, Yandex и др.):"
echo "Обязательно открой порт $PROXY_PORT (TCP/UDP) в панели"
echo "управления сервером на сайте твоего хостинг-провайдера!"
echo "==================================================="
echo "💡 Если у вас были старые или новые клиенты (конфиги) в /root,"
echo "переместите их в $CLIENTS_DIR вручную для"
echo "отображения в панели управления."
echo "==================================================="
echo "🔥 Для вызова панели управления просто напиши: vk-panel"
echo "==================================================="
