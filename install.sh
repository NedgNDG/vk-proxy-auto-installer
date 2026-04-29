#!/bin/bash

# === НАСТРОЙКИ ===
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (команда: sudo bash)"
  exit 1
fi

# === ФУНКЦИЯ СОЗДАНИЯ ПАНЕЛИ ===
create_panel() {
cat << 'EOF' > /usr/local/bin/vk-panel
#!/bin/bash
INSTALLER_URL="https://raw.githubusercontent.com/NedgNDG/vk-proxy-auto-installer/main/install.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

# Принудительно получаем IPv4
PUBLIC_IP=$(curl -4 -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 https://api.ipify.org)

if [[ -f /root/.vk-proxy-version ]]; then CURRENT_VERSION=$(cat /root/.vk-proxy-version); else CURRENT_VERSION="Неизвестно"; fi
if [[ -f /root/.vk-proxy-port ]]; then PROXY_PORT=$(cat /root/.vk-proxy-port); else PROXY_PORT="56000"; fi

# Получаем целевой порт
if [[ -f /root/.vk-proxy-target-port ]]; then 
    TARGET_PORT=$(cat /root/.vk-proxy-target-port)
else 
    TARGET_PORT=$(grep -oP '(?:-connect |-p )127\.0\.0\.1:\K\d+' /etc/systemd/system/vk-proxy.service | head -1)
    TARGET_PORT=${TARGET_PORT:-51820}
    echo "$TARGET_PORT" > /root/.vk-proxy-target-port
fi

# Читаем и мигрируем репозиторий
if [[ -f /root/.vk-proxy-repo ]]; then 
    PROXY_REPO=$(cat /root/.vk-proxy-repo)
    if [[ "$PROXY_REPO" != *"/"* ]] && [[ "$PROXY_REPO" != "Прямая ссылка" ]]; then
        if [[ "$PROXY_REPO" == "Urtyom-Alyanov" ]]; then
            PROXY_REPO="Urtyom-Alyanov/turn-proxy"
        else
            PROXY_REPO="${PROXY_REPO}/vk-turn-proxy"
        fi
        echo "$PROXY_REPO" > /root/.vk-proxy-repo
    fi
    # Миграция alexmac6574 -> alxmcp
    if [[ "$PROXY_REPO" == "alexmac6574/vk-turn-proxy" ]]; then
        PROXY_REPO="alxmcp/vk-turn-proxy"
        echo "$PROXY_REPO" > /root/.vk-proxy-repo
    fi
else 
    PROXY_REPO="cacggghp/vk-turn-proxy"
fi

# Автоматическая миграция со старого флага -telemost-dc на новый -dc
if [[ -f /root/.vk-proxy-yandex-dc ]]; then
    mv /root/.vk-proxy-yandex-dc /root/.vk-proxy-dc-mode
    MIGRATION_NEEDED=1
fi

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
    if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
        FINAL_ARGS=$(cat /root/.vk-proxy-custom-args)
    else
        local VLESS_FLAG=""
        local DC_FLAG=""
        
        if [[ -f /root/.vk-proxy-vless ]] && [[ "$(cat /root/.vk-proxy-vless)" == "1" ]]; then 
            VLESS_FLAG=" -vless"
        fi
        
        if [[ -f /root/.vk-proxy-dc-mode ]] && [[ "$(cat /root/.vk-proxy-dc-mode)" == "1" ]]; then
            if [[ -f /root/.vk-proxy-jazz-room ]]; then
                local JAZZ_ROOM=$(cat /root/.vk-proxy-jazz-room)
                DC_FLAG=" -jazz-room $JAZZ_ROOM -dc"
            elif [[ -f /root/.vk-proxy-yandex-link ]]; then
                local LINK=$(cat /root/.vk-proxy-yandex-link)
                DC_FLAG=" -yandex-link $LINK -dc"
            fi
        fi

        local CORE_TYPE="go"
        if [[ -f /root/.vk-proxy-core-type ]]; then
            CORE_TYPE=$(cat /root/.vk-proxy-core-type)
        elif [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
            CORE_TYPE="rust"
        fi

        if [[ "$CORE_TYPE" == "rust" ]]; then
            FINAL_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000$DC_FLAG$VLESS_FLAG"
        else
            FINAL_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$DC_FLAG$VLESS_FLAG"
        fi
    fi
    echo "$FINAL_ARGS"
}

# Применяем миграцию, если это необходимо
if [[ "$MIGRATION_NEEDED" == "1" ]]; then
    EXEC_ARGS=$(get_exec_args)
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
fi

while true; do
    clear
    
    TARGET_SERVICE="Введен вручную / Неизвестен"
    shopt -s nullglob
    for conf in /etc/hysteria/*.yaml /etc/hysteria/*.json; do
        port=$(grep -i -oP -m 1 '^listen:\s*(?:.*:)?\K\d+' "$conf" 2>/dev/null)
        if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="Hysteria2"; break; fi
    done
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf; do
            port=$(grep -oP -m 1 'ListenPort\s*=\s*\K\d+' "$conf" 2>/dev/null)
            if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="AmneziaWG"; break; fi
        done
    fi
    if [[ "$TARGET_SERVICE" == "Введен вручную / Неизвестен" ]]; then
        for conf in /etc/wireguard/*.conf; do
            port=$(grep -oP -m 1 'ListenPort\s*=\s*\K\d+' "$conf" 2>/dev/null)
            if [[ "$port" == "$TARGET_PORT" ]]; then TARGET_SERVICE="WireGuard"; break; fi
        done
    fi
    shopt -u nullglob

    if systemctl is-active --quiet vk-proxy; then PROXY_STATE="${GREEN}Активен${NC}"; else PROXY_STATE="${RED}Остановлен${NC}"; fi
    if [[ -f /root/.vk-proxy-vless ]] && [[ "$(cat /root/.vk-proxy-vless)" == "1" ]]; then VLESS_TEXT="${GREEN}Включен${NC}"; else VLESS_TEXT="${RED}Выключен${NC}"; fi
    if [[ -f /root/.vk-proxy-dc-mode ]] && [[ "$(cat /root/.vk-proxy-dc-mode)" == "1" ]]; then DC_TEXT="${GREEN}Включен${NC}"; else DC_TEXT="${RED}Выключен${NC}"; fi
    
    if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
        MODE_TEXT="${YELLOW}Кастомные аргументы (Raw)${NC}"
    else
        MODE_TEXT="${GREEN}Автоматический${NC}"
    fi

	echo "========================================================================="
    echo -e "${CYAN}                       VK TURN Proxy Manager v1.9b                       ${NC}"
    echo "========================================================================="
    echo -e " 🟢 Статус:      ${PROXY_STATE}"
    echo -e " 📦 Версия:      ${YELLOW}${CURRENT_VERSION}${NC} (Ядро: ${CYAN}${PROXY_REPO}${NC})"
    echo -e " ⚙️  Режим:       ${MODE_TEXT}"
    echo -e " 🛡️  VLESS:       ${VLESS_TEXT}  |  📞 DataChannel: ${DC_TEXT}"
    echo "-------------------------------------------------------------------------"
    echo -e " 🌐 Внешний:     ${PUBLIC_IP}:${PROXY_PORT}"
    echo -e " 🎯 Назначение:  127.0.0.1:${TARGET_PORT} [${YELLOW}${TARGET_SERVICE}${NC}]"
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
    echo "  8. 🛡️ Включить/Выключить флаг '-vless'"
    echo "  9. 📞 Включить/Выключить режим 'DataChannel (SaluteJazz / Yandex)'"
    echo " 10. ✍️ Задать кастомные аргументы запуска (Raw command)"
    echo ""
    echo -e "${YELLOW}--- VPN и Клиенты ---${NC}"
    echo " 11. ➕ Установка/Управление VPN (WG / AmneziaWG / Hysteria2)"
    echo " 12. 📱 Показать QR-код существующего клиента"
    echo ""
    echo -e "${YELLOW}--- Система ---${NC}"
    echo " 13. 📊 Посмотреть логи"
    echo " 14. ⚙️ Обновить панель"
    echo "  0. ❌ Выйти"
    echo "========================================================================="
    read -p "Выбери действие: " choice

    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"

    case $choice in
        1) systemctl start vk-proxy; echo -e "${GREEN}Запущено!${NC}"; sleep 1 ;;
        2) systemctl stop vk-proxy; echo -e "${RED}Остановлено!${NC}"; sleep 1 ;;
        3) if systemctl restart vk-proxy; then echo -e "${GREEN}Успешно перезапущено!${NC}"; else echo -e "${RED}Ошибка перезапуска! Проверьте логи (Пункт 13).${NC}"; fi; sleep 2 ;;
        4)
            if [[ "$PROXY_REPO" == "Прямая ссылка" || "$PROXY_REPO" == "Custom_Direct_Link" ]]; then
                echo -e "${YELLOW}Ядро установлено по прямой ссылке. Автоматическое обновление через API недоступно.${NC}"
                echo "Для обновления используйте пункт 5 (Сменить реализацию) и вставьте новую прямую ссылку."
                read -n 1 -s -r -p "Нажми любую клавишу..."
                continue
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
                    if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
                        echo -e "${RED}Ошибка получения ссылки на скачивание. Отмена.${NC}"
                    else
                        echo "Скачивание обновления..."
                        if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                            systemctl stop vk-proxy
                            mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                            chmod +x /root/server-linux-$SYS_ARCH
                            
                            EXEC_ARGS=$(get_exec_args)
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
                            
                            echo "$LATEST_TAG" > /root/.vk-proxy-version
                            systemctl start vk-proxy
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
            echo -e "${YELLOW}======================================================${NC}"
            echo -e "${YELLOW}ВНИМАНИЕ: При смене реализации ваши текущие клиенты   ${NC}"
            echo -e "${YELLOW}могут перестать подключаться! Возможно, потребуется   ${NC}"
            echo -e "${YELLOW}перенастройка на стороне клиента или его смена.       ${NC}"
            echo -e "${YELLOW}======================================================${NC}"
            echo -e "Текущая реализация: ${CYAN}${PROXY_REPO}${NC}"
            echo "Доступные реализации:"
            echo -e "1) cacggghp/vk-turn-proxy (Оригинал)"
            echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
            echo -e "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust, только amd64/x86_64)"
            echo -e "4) Moroka8/vk-turn-proxy (Форк)"
            echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка Yandex / SaluteJazz\e[0m)"
            echo -e "6) samosvalishe/vk-turn-proxy (Форк)"
            echo -e "7) Сторонний репозиторий GitHub ИЛИ прямая ссылка на бинарник"
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
                    read -p "Введи репозиторий (owner/repo) ИЛИ прямую ссылку на бинарный файл: " custom_input
                    if [[ "$custom_input" =~ ^https?:// ]] && [[ ! "$custom_input" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
                        NEW_REPO="Custom_Direct_Link"
                        DOWNLOAD_URL="$custom_input"
                        LATEST_TAG="Custom"
                    else
                        NEW_REPO=$(echo "$custom_input" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
                        if [[ -z "$NEW_REPO" || "$NEW_REPO" != *"/"* || "$NEW_REPO" == "/" ]]; then
                            echo -e "${RED}Неверный формат.${NC}"
                            sleep 1; continue
                        fi
                    fi
                    
                    echo -e "\n${CYAN}Какой тип аргументов использовать для этого кастомного ядра?${NC}"
                    echo "1) Стандартные (Go: -listen 0.0.0.0:PORT -connect 127.0.0.1:PORT)"
                    echo "2) Rust (Urtyom-Alyanov: -N -l 0.0.0.0:PORT -p 127.0.0.1:PORT)"
                    echo "3) Задать вручную (Raw command)"
                    read -p "Твой выбор [1-3]: " custom_core_type
                    if [[ "$custom_core_type" == "2" ]]; then
                        NEW_CORE_TYPE="rust"
                    elif [[ "$custom_core_type" == "3" ]]; then
                        NEW_CORE_TYPE="custom"
                    else
                        NEW_CORE_TYPE="go"
                    fi
                    ;;
                0) continue ;;
                *) echo -e "${RED}Неверный выбор.${NC}"; sleep 1; continue ;;
            esac
            
            if [[ "$NEW_REPO" == "$PROXY_REPO" ]]; then
                echo -e "${YELLOW}Эта реализация уже установлена!${NC}"; sleep 1; continue
            fi
            
            read -p "Вы уверены, что хотите сменить ядро? [y/N]: " confirm_switch
            if [[ "$confirm_switch" =~ ^[Yy]$ ]]; then
                
                if [[ "$NEW_REPO" == "Custom_Direct_Link" ]]; then
                    echo "Скачивание ядра по прямой ссылке..."
                    if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                        systemctl stop vk-proxy
                        mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                        chmod +x /root/server-linux-$SYS_ARCH
                        
                        PROXY_REPO="Прямая ссылка"
                        
                        echo "$NEW_CORE_TYPE" > /root/.vk-proxy-core-type
                        if [[ "$NEW_CORE_TYPE" == "custom" ]]; then
                            echo -e "\nВведи кастомные аргументы (например: -listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless)"
                            read -p "Аргументы: " manual_custom_args
                            echo "$manual_custom_args" > /root/.vk-proxy-custom-args
                        else
                            rm -f /root/.vk-proxy-custom-args
                        fi
                        
                        EXEC_ARGS=$(get_exec_args)

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
                        
                        echo "Прямая ссылка" > /root/.vk-proxy-repo
                        echo "Custom" > /root/.vk-proxy-version
                        systemctl start vk-proxy
                        CURRENT_VERSION="Custom"
                        echo -e "${GREEN}Успешно обновлено по прямой ссылке!${NC}"
                    else
                        echo -e "${RED}Ошибка скачивания по прямой ссылке. Отмена.${NC}"
                    fi
                else
                    echo "Получение данных с GitHub ($NEW_REPO)..."
                    NEW_API_URL="https://api.github.com/repos/${NEW_REPO}/releases/latest"
                    API_RESP=$(curl -s --connect-timeout 10 "$NEW_API_URL")
                    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
                    
                    if [[ "$LATEST_TAG" == "null" || -z "$LATEST_TAG" ]]; then
                        echo -e "${RED}Ошибка API GitHub (возможно исчерпан лимит или нет релизов). Отмена.${NC}"
                    else
                        DOWNLOAD_URL=$(get_download_url "$API_RESP" "$SYS_ARCH" "$NEW_REPO")
                        if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
                            echo -e "${RED}Ошибка получения релиза $NEW_REPO. Возможно бинарник не опубликован. Отмена.${NC}"
                        else
                            echo "Скачивание ядра..."
                            if wget -q --show-progress -O /tmp/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
                                systemctl stop vk-proxy
                                mv /tmp/server-linux-$SYS_ARCH /root/server-linux-$SYS_ARCH
                                chmod +x /root/server-linux-$SYS_ARCH
                                
                                PROXY_REPO=$NEW_REPO
                                
                                echo "$NEW_CORE_TYPE" > /root/.vk-proxy-core-type
                                if [[ "$NEW_CORE_TYPE" == "custom" ]]; then
                                    echo -e "\nВведи кастомные аргументы (например: -listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless)"
                                    read -p "Аргументы: " manual_custom_args
                                    echo "$manual_custom_args" > /root/.vk-proxy-custom-args
                                else
                                    rm -f /root/.vk-proxy-custom-args
                                fi
                                
                                EXEC_ARGS=$(get_exec_args)

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
                                
                                echo "$NEW_REPO" > /root/.vk-proxy-repo
                                echo "$LATEST_TAG" > /root/.vk-proxy-version
                                systemctl start vk-proxy
                                CURRENT_VERSION=$LATEST_TAG
                                echo -e "${GREEN}Успешно изменено на реализацию $NEW_REPO ($LATEST_TAG)!${NC}"
                            else
                                echo -e "${RED}Ошибка скачивания ядра. Отмена.${NC}"
                            fi
                        fi
                    fi
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..."
            ;;
        6)
            echo -e "${RED}ВНИМАНИЕ: Это удалит службу и бинарник прокси! Остальные VPN (WG, AmneziaWG, Hysteria2) останутся нетронутыми.${NC}"
            read -p "Вы АБСОЛЮТНО уверены? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop vk-proxy; systemctl disable vk-proxy; rm -f /etc/systemd/system/vk-proxy.service; systemctl daemon-reload
                if command -v ufw &> /dev/null; then ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1; ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1; fi
                rm -f /root/server-linux-$SYS_ARCH /root/.vk-proxy-version /usr/local/bin/vk-panel /root/.vk-proxy-repo /root/.vk-proxy-core-type /root/.vk-proxy-port /root/.vk-proxy-target-port /root/.vk-proxy-vless /root/.vk-proxy-custom-args /root/.vk-proxy-yandex-link /root/.vk-proxy-dc-mode /root/.vk-proxy-jazz-room /root/.vk-proxy-yandex-dc
                echo -e "${GREEN}Прокси успешно удален.${NC}"; exit 0
            fi ;;
        7)
            echo ""
            if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
                echo -e "${YELLOW}⚠️ ВНИМАНИЕ: У вас активны кастомные аргументы запуска!${NC}"
                echo -e "Изменения портов сохранятся, но ${RED}НЕ ПРИМЕНЯТСЯ${NC} к службе, пока вы не сбросите кастомные настройки (пункт 10)."
                echo ""
            fi
            
            echo -e "${CYAN}Изменение портов:${NC}"
            echo "1) Изменить внешний порт прокси (сейчас: $PROXY_PORT)"
            echo "2) Изменить локальный порт назначения (сейчас: $TARGET_PORT)"
            echo "0) Отмена"
            read -p "Что будем менять? [1, 2 или 0]: " port_change_choice

            if [[ "$port_change_choice" == "1" ]]; then
                read -p "Введи новый внешний порт (от 1 до 65535): " NEW_PROXY_PORT
                if [[ "$NEW_PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PROXY_PORT" -ge 1 ] && [ "$NEW_PROXY_PORT" -le 65535 ]; then
                    if command -v ss &> /dev/null && ss -tuln | grep -qE ":$NEW_PROXY_PORT\b"; then
                        echo -e "${RED}⚠️ Ошибка: Порт $NEW_PROXY_PORT уже занят. Выбери другой.${NC}"
                    else
                        if command -v ufw &> /dev/null; then
                            echo "Обновление правил UFW..."
                            ufw delete allow $PROXY_PORT/tcp >/dev/null 2>&1
                            ufw delete allow $PROXY_PORT/udp >/dev/null 2>&1
                            ufw allow $NEW_PROXY_PORT/tcp >/dev/null 2>&1
                            ufw allow $NEW_PROXY_PORT/udp >/dev/null 2>&1
                        fi
                        echo "$NEW_PROXY_PORT" > /root/.vk-proxy-port
                        PROXY_PORT="$NEW_PROXY_PORT"
                        echo -e "${GREEN}Внешний порт изменен на $PROXY_PORT!${NC}"
                    fi
                else
                    echo -e "${RED}Неверный формат порта.${NC}"
                fi

            elif [[ "$port_change_choice" == "2" ]]; then
                echo ""
                echo "Как задать новый локальный порт?"
                echo "1) Ввести вручную"
                echo "2) Найти автоматически в установленных конфигурациях VPN (WG/AWG/Hysteria2)"
                read -p "Твой выбор: " target_port_method

                NEW_TARGET_PORT=""

                if [[ "$target_port_method" == "1" ]]; then
                    read -p "Введи новый локальный порт (например, 51820 или 443): " input_target_port
                    if [[ "$input_target_port" =~ ^[0-9]+$ ]] && [ "$input_target_port" -ge 1 ] && [ "$input_target_port" -le 65535 ]; then
                        NEW_TARGET_PORT="$input_target_port"
                    else
                        echo -e "${RED}Неверный формат порта.${NC}"
                    fi
                elif [[ "$target_port_method" == "2" ]]; then
                    shopt -s nullglob
                    ALL_CONFS=(/etc/wireguard/*.conf /etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf /etc/hysteria/*.yaml /etc/hysteria/*.json)
                    shopt -u nullglob

                    if [ ${#ALL_CONFS[@]} -eq 0 ]; then
                        echo -e "${RED}Файлы конфигураций VPN не найдены на сервере.${NC}"
                    else
                        echo -e "${YELLOW}Найдены следующие конфигурации:${NC}"
                        for i in "${!ALL_CONFS[@]}"; do
                            port=$(grep -i -oP -m 1 '(ListenPort\s*=\s*|^listen:\s*(?:.*:)?)\K\d+' "${ALL_CONFS[$i]}")
                            echo "$((i+1)). ${ALL_CONFS[$i]} (Найденный порт: ${port:-не обнаружен})"
                        done
                        echo ""
                        read -p "Выбери номер конфигурации для привязки: " conf_choice
                        if [[ "$conf_choice" -ge 1 && "$conf_choice" -le ${#ALL_CONFS[@]} ]]; then
                            NEW_TARGET_PORT=$(grep -i -oP -m 1 '(ListenPort\s*=\s*|^listen:\s*(?:.*:)?)\K\d+' "${ALL_CONFS[$((conf_choice-1))]}")
                            if [[ -z "$NEW_TARGET_PORT" ]]; then
                                echo -e "${RED}В выбранном файле не найден порт.${NC}"
                            fi
                        else
                            echo -e "${RED}Неверный выбор.${NC}"
                        fi
                    fi
                fi

                if [[ -n "$NEW_TARGET_PORT" ]]; then
                    echo "$NEW_TARGET_PORT" > /root/.vk-proxy-target-port
                    TARGET_PORT="$NEW_TARGET_PORT"
                    echo -e "${GREEN}Локальный порт изменен на $TARGET_PORT!${NC}"
                fi
            fi

            if [[ "$port_change_choice" == "1" || "$port_change_choice" == "2" ]]; then
                EXEC_ARGS=$(get_exec_args)

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
                if systemctl restart vk-proxy; then
                    echo -e "${CYAN}Служба прокси успешно перезапущена!${NC}"
                else
                    echo -e "${RED}Ошибка перезапуска службы. Проверьте логи.${NC}"
                fi
            fi
            
            read -n 1 -s -r -p "Нажми любую клавишу..."
            ;;
        8)
            if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
                echo -e "${YELLOW}⚠️ ВНИМАНИЕ: У вас активны кастомные аргументы запуска!${NC}"
                echo -e "Флаг сохранится, но ${RED}НЕ ПРИМЕНИТСЯ${NC} к службе, пока вы не сбросите кастомные настройки (пункт 10)."
                echo ""
            fi

            if [[ -f /root/.vk-proxy-vless ]] && [[ "$(cat /root/.vk-proxy-vless)" == "1" ]]; then
                echo "0" > /root/.vk-proxy-vless
                echo -e "${YELLOW}Флаг -vless будет отключен.${NC}"
            else
                echo "1" > /root/.vk-proxy-vless
                echo -e "${GREEN}Флаг -vless будет добавлен.${NC}"
            fi

            EXEC_ARGS=$(get_exec_args)

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
            echo -e "${GREEN}Конфигурация обновлена и служба перезапущена!${NC}"
            sleep 2
            ;;
        9)
            echo ""
            if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
                echo -e "${YELLOW}⚠️ ВНИМАНИЕ: У вас активны кастомные аргументы запуска!${NC}"
                echo -e "Настройки DataChannel сохранятся, но ${RED}НЕ ПРИМЕНЯТСЯ${NC} к службе, пока вы не сбросите кастомные настройки (пункт 10)."
                echo ""
            fi

            if [[ -f /root/.vk-proxy-dc-mode ]] && [[ "$(cat /root/.vk-proxy-dc-mode)" == "1" ]]; then
                echo "0" > /root/.vk-proxy-dc-mode
                echo -e "${YELLOW}Режим DataChannel будет отключен.${NC}"
            else
                echo -e "${CYAN}Настройка DataChannel (без TURN)${NC}"
                echo "1) SaluteJazz"
                echo "2) Яндекс Телемост"
                read -p "Выберите сервис [1-2]: " dc_choice

                if [[ "$dc_choice" == "1" ]]; then
                    read -p "Введи комнату (нажми Enter для 'any' - сервер создаст случайную, название и пароль смотрите в логах): " input_room
                    input_room=${input_room:-any}
                    echo "$input_room" > /root/.vk-proxy-jazz-room
                    rm -f /root/.vk-proxy-yandex-link
                    echo "1" > /root/.vk-proxy-dc-mode
                    echo -e "${GREEN}Режим SaluteJazz DataChannel будет включен!${NC}"
                elif [[ "$dc_choice" == "2" ]]; then
                    read -p "Введи ссылку на звонок Yandex (начинается с https://telemost.yandex.ru/j/): " input_link
                    if [[ -n "$input_link" ]]; then
                        echo "$input_link" > /root/.vk-proxy-yandex-link
                        rm -f /root/.vk-proxy-jazz-room
                        echo "1" > /root/.vk-proxy-dc-mode
                        echo -e "${GREEN}Режим Yandex Telemost DataChannel будет включен!${NC}"
                    else
                        echo -e "${RED}Ссылка не введена. Отмена.${NC}"
                        sleep 2
                        continue
                    fi
                else
                    echo -e "${RED}Неверный выбор. Отмена.${NC}"
                    sleep 2
                    continue
                fi
            fi

            EXEC_ARGS=$(get_exec_args)

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
            echo -e "${GREEN}Конфигурация обновлена и служба перезапущена!${NC}"
            sleep 2
            ;;
        10)
            echo ""
            echo -e "${CYAN}Кастомные аргументы запуска (Raw command)${NC}"
            echo -e "Внимание: если задать кастомные аргументы, настройки портов, DataChannel и флага -vless из панели ${RED}будут игнорироваться${NC}!"
            echo "Если меняешь внешний порт в этом режиме, не забудь открыть его в UFW вручную."
            echo ""
            echo -e "Текущие аргументы:"
            if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
                echo -e "${YELLOW}$(cat /root/.vk-proxy-custom-args)${NC}"
            else
                echo -e "${GREEN}Не заданы (используется автоматический режим)${NC}"
            fi
            echo ""
            echo "Введи новые аргументы (например: -listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless)"
            echo "Или просто нажми Enter, чтобы СБРОСИТЬ кастомные аргументы и вернуться к автоматике."
            read -p "Аргументы: " input_custom
            if [[ -z "$input_custom" ]]; then
                rm -f /root/.vk-proxy-custom-args
                echo -e "${GREEN}Сброшено на автоматический режим! Возвращаем стандартные флаги.${NC}"
            else
                echo "$input_custom" > /root/.vk-proxy-custom-args
                echo -e "${GREEN}Кастомные аргументы сохранены!${NC}"
            fi

            EXEC_ARGS=$(get_exec_args)

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
            echo -e "${GREEN}Служба перезапущена с новыми аргументами!${NC}"
            read -n 1 -s -r -p "Нажми любую клавишу..."
            ;;
        11) 
            echo ""
            echo -e "${CYAN}Управление и установка VPN:${NC}"
            echo "1) WireGuard"
            echo "2) AmneziaWG"
            echo "3) Hysteria2"
            read -p "Выбери вариант: " vpn_manage_choice
            if [[ "$vpn_manage_choice" == "1" || "$vpn_manage_choice" == "2" || "$vpn_manage_choice" == "3" ]]; then
                read -p "Вы точно хотите установить/управлять этим VPN? [y/N]: " confirm_vpn
                if [[ "$confirm_vpn" =~ ^[Yy]$ ]]; then
                    if [[ "$vpn_manage_choice" == "1" ]]; then
                        if [ ! -f /root/wireguard-install.sh ]; then
                            echo -e "${YELLOW}Установщик WireGuard не найден. Скачивание...${NC}"
                            curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
                            chmod +x /root/wireguard-install.sh
                        fi
                        bash /root/wireguard-install.sh
                    elif [[ "$vpn_manage_choice" == "2" ]]; then
                        if [ ! -f /root/amneziawg-install.sh ]; then
                            echo -e "${YELLOW}Установщик AmneziaWG не найден. Скачивание...${NC}"
                            curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh
                            chmod +x /root/amneziawg-install.sh
                        fi
                        bash /root/amneziawg-install.sh
                    elif [[ "$vpn_manage_choice" == "3" ]]; then
                        if [ ! -f /root/hysteria-install.sh ]; then
                            echo -e "${YELLOW}Установщик Hysteria2 не найден. Скачивание...${NC}"
                            curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh
                            chmod +x /root/hysteria-install.sh
                        fi
                        bash /root/hysteria-install.sh
                    fi
                else
                    echo -e "${YELLOW}Действие отменено.${NC}"
                fi
            else
                echo -e "${RED}Неверный выбор.${NC}"
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." 
            ;;
        12)
            echo ""
            echo -e "${CYAN}Доступные конфигурации клиентов:${NC}"
            
            # Собираем массив файлов из /root (включая 1 уровень вложенности, игнорируя скрытые папки)
            CLIENT_CONFS=()
            while IFS= read -r file; do
                CLIENT_CONFS+=("$file")
            done < <(find /root -maxdepth 2 -name ".*" -prune -o -type f \( -name "*.conf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.txt" \) -print 2>/dev/null)

            if [ ${#CLIENT_CONFS[@]} -eq 0 ]; then
                echo -e "${RED}Файлы конфигурации клиентов (.conf, .yaml, .txt...) не найдены в /root/${NC}"
                echo -e "${YELLOW}Возможно, установщик Hysteria2 не сохранил конфиг в виде файла, а просто вывел ссылку (hy2://...) в консоль при установке.${NC}"
            else
                for i in "${!CLIENT_CONFS[@]}"; do
                    # Красиво выводим имя файла с путем (чтобы было видно, если он в папке)
                    echo "$((i+1)). ${CLIENT_CONFS[$i]}"
                done
                echo ""
                read -p "Выбери номер клиента для показа QR-кода (или 0 для отмены): " qr_choice
                if [[ "$qr_choice" == "0" ]]; then
                    continue
                elif [[ "$qr_choice" -ge 1 && "$qr_choice" -le ${#CLIENT_CONFS[@]} ]]; then
                    TARGET_CONF="${CLIENT_CONFS[$((qr_choice-1))]}"
                    echo -e "${GREEN}QR-код для $(basename "$TARGET_CONF"):${NC}"
                    
                    qrencode -t ansiutf8 < "$TARGET_CONF"
                else
                    echo -e "${RED}Неверный выбор.${NC}"
                fi
            fi
            read -n 1 -s -r -p "Нажми любую клавишу..." 
            ;;
        13) journalctl -u vk-proxy -n 20 --no-pager; read -n 1 -s -r -p "Нажми любую клавишу..." ;;
        14)
            echo -e "${YELLOW}Скачивание обновления панели...${NC}"
            bash <(curl -sfL --connect-timeout 10 "$INSTALLER_URL") --update-panel
            echo -e "${GREEN}Панель обновлена! Перезапустите команду vk-panel.${NC}"
            exit 0 ;;
        0) clear; exit 0 ;;
        *) echo "Неверный выбор!"; sleep 1 ;;
    esac
done
EOF
chmod +x /usr/local/bin/vk-panel
}

# 0. Быстрое обновление только панели (скрытый режим)
if [[ "$1" == "--update-panel" ]]; then
    echo "Обновление панели vk-panel..."
    create_panel
    exit 0
fi

clear
echo "==================================================="
echo "   Ультимативный Установщик VPN + vk-turn-proxy    "
echo "==================================================="
echo ""

if [[ -f /root/.vk-proxy-yandex-dc ]]; then
    mv /root/.vk-proxy-yandex-dc /root/.vk-proxy-dc-mode
fi

# 1. Проверка зависимостей
echo "[1/9] Установка зависимостей (curl, wget, jq, ufw, qrencode)..."
if command -v apt-get &> /dev/null; then
    apt-get update -y > /dev/null 2>&1
    apt-get install -y curl wget jq ufw qrencode > /dev/null 2>&1
elif command -v yum &> /dev/null; then
    yum install -y curl wget jq epel-release > /dev/null 2>&1
    yum install -y ufw qrencode > /dev/null 2>&1
fi

# 2. Архитектура
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then SYS_ARCH="amd64"; else SYS_ARCH="arm64"; fi

# 3. Выбор реализации
echo ""
echo "[2/9] Выбор реализации vk-turn-proxy..."
echo -e "1) cacggghp/vk-turn-proxy (Оригинал, по умолчанию)"
echo -e "2) kiper292/vk-turn-proxy (Форк, \e[9mподдержка WB Stream\e[0m)"
echo -e "3) Urtyom-Alyanov/turn-proxy (Ядро на Rust, только amd64/x86_64)"
echo -e "4) Moroka8/vk-turn-proxy (Форк)"
echo -e "5) alxmcp/vk-turn-proxy (Форк, \e[9mподдержка DataChannel SaluteJazz / Yandex\e[0m)"
echo -e "6) samosvalishe/vk-turn-proxy (Форк)"
echo -e "7) Сторонний репозиторий GitHub ИЛИ прямая ссылка на бинарник"
read -p "Твой выбор [1-7]: " repo_choice

case "$repo_choice" in
  2) PROXY_REPO="kiper292/vk-turn-proxy"; echo "go" > /root/.vk-proxy-core-type ;;
  3) PROXY_REPO="Urtyom-Alyanov/turn-proxy"; echo "rust" > /root/.vk-proxy-core-type ;;
  4) PROXY_REPO="Moroka8/vk-turn-proxy"; echo "go" > /root/.vk-proxy-core-type ;;
  5) PROXY_REPO="alxmcp/vk-turn-proxy"; echo "go" > /root/.vk-proxy-core-type ;;
  6) PROXY_REPO="samosvalishe/vk-turn-proxy"; echo "go" > /root/.vk-proxy-core-type ;;
  7)
     read -p "Введи репозиторий (owner/repo) ИЛИ прямую ссылку на бинарный файл: " custom_input
     if [[ "$custom_input" =~ ^https?:// ]] && [[ ! "$custom_input" =~ ^https?://(www\.)?github\.com/[^/]+/[^/]+/?$ ]]; then
         PROXY_REPO="Custom_Direct_Link"
         DOWNLOAD_URL="$custom_input"
         LATEST_TAG="Custom"
     else
         PROXY_REPO=$(echo "$custom_input" | sed -E 's|^https?://github\.com/||' | sed 's/\.git$//' | awk -F/ '{print $1"/"$2}')
         if [[ -z "$PROXY_REPO" || "$PROXY_REPO" != *"/"* || "$PROXY_REPO" == "/" ]]; then
             echo "Неверный формат. Используем оригинал."
             PROXY_REPO="cacggghp/vk-turn-proxy"
             echo "go" > /root/.vk-proxy-core-type
         fi
     fi
     
     if [[ "$PROXY_REPO" == "Custom_Direct_Link" || "$PROXY_REPO" != "cacggghp/vk-turn-proxy" ]]; then
         echo -e "\nКакой тип аргументов использовать для этого кастомного ядра?"
         echo "1) Стандартные (Go: -listen 0.0.0.0:PORT -connect 127.0.0.1:PORT)"
         echo "2) Rust (Urtyom-Alyanov: -N -l 0.0.0.0:PORT -p 127.0.0.1:PORT)"
         echo "3) Задать вручную (Raw command)"
         read -p "Твой выбор [1-3]: " custom_core_type
         if [[ "$custom_core_type" == "2" ]]; then
             echo "rust" > /root/.vk-proxy-core-type
         elif [[ "$custom_core_type" == "3" ]]; then
             echo "custom" > /root/.vk-proxy-core-type
         else
             echo "go" > /root/.vk-proxy-core-type
         fi
     fi
     ;;
  *) PROXY_REPO="cacggghp/vk-turn-proxy"; echo "go" > /root/.vk-proxy-core-type ;;
esac

# 4. Выбор порта прокси
echo ""
echo "[3/9] Настройка внешнего порта прокси (к нему будут подключаться клиенты через VK)..."
DEFAULT_PROXY_PORT=56000
if [[ -f /root/.vk-proxy-core-type ]] && [[ "$(cat /root/.vk-proxy-core-type)" == "rust" ]]; then
    DEFAULT_PROXY_PORT=56040
fi

while true; do
    read -p "Введи внешний порт прокси (нажми Enter для $DEFAULT_PROXY_PORT): " INPUT_PROXY_PORT
    if [[ -z "$INPUT_PROXY_PORT" ]]; then
        INPUT_PROXY_PORT="$DEFAULT_PROXY_PORT"
    fi

    if [[ "$INPUT_PROXY_PORT" =~ ^[0-9]+$ ]] && [ "$INPUT_PROXY_PORT" -ge 1 ] && [ "$INPUT_PROXY_PORT" -le 65535 ]; then
        if command -v ss &> /dev/null && ss -tuln | grep -qE ":$INPUT_PROXY_PORT\b"; then
            echo "⚠️ Ошибка: Порт $INPUT_PROXY_PORT уже занят другим приложением. Выбери другой."
        else
            PROXY_PORT="$INPUT_PROXY_PORT"
            break
        fi
    else
        echo "⚠️ Ошибка: Введи корректный порт от 1 до 65535."
    fi
done

echo "$PROXY_PORT" > /root/.vk-proxy-port
echo "Выбран внешний порт: $PROXY_PORT"

# Выбор использования флага -vless при установке
echo ""
echo "[4/9] Использовать флаг -vless?"
echo "Некоторые клиенты (например, VLESS) и обновленные ядра могут использовать этот флаг, даёт возможность гнать трафик по этому протоколу."
read -p "Включить флаг -vless по умолчанию? [y/N]: " use_vless
if [[ "$use_vless" =~ ^[Yy]$ ]]; then
    echo "1" > /root/.vk-proxy-vless
else
    echo "0" > /root/.vk-proxy-vless
fi

# 5. Выбор типа установки и настройка целевого локального порта
echo ""
echo "[5/9] Настройка локального порта (цель для прокси)..."
echo "Куда прокси должен перенаправлять трафик?"
echo "1) Установить WireGuard с нуля (автоматически установит и привяжет порт)"
echo "2) Установить AmneziaWG с нуля (автоматически установит и привяжет порт)"
echo "3) Установить Hysteria2 с нуля (автоматически установит и привяжет порт)"
echo "4) Ввести порт вручную (если WG/AWG, Hysteria2, Xray или 3X-UI уже установлены)"
read -p "Твой выбор [1-4]: " port_setup_choice

TARGET_PORT=""

if [[ "$port_setup_choice" == "4" ]]; then
    echo ""
    read -p "Введи локальный порт (например, 51820 для WG/AWG, 443 для Hysteria2/Xray/VLESS): " manual_port
    if [[ "$manual_port" =~ ^[0-9]+$ ]] && [ "$manual_port" -ge 1 ] && [ "$manual_port" -le 65535 ]; then
        TARGET_PORT="$manual_port"
        echo "Выбран ручной порт: $TARGET_PORT"
    else
        echo "Ошибка: введено некорректное значение порта. Используем стандартный порт: 51820"
        TARGET_PORT=51820
    fi
elif [[ "$port_setup_choice" == "3" ]]; then
    echo ""
    echo "[6/9] Установка и поиск порта Hysteria2..."
    shopt -s nullglob
    HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json)
    shopt -u nullglob

    if [ ${#HYS_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации Hysteria2."
        read -p "Хочешь запустить установщик Hysteria2? (выбери N, если Hysteria2 уже настроен) [y/N]: " run_hys
        if [[ "$run_hys" =~ ^[Yy]$ ]]; then
            if curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; then
                chmod +x /root/hysteria-install.sh
                bash /root/hysteria-install.sh
            else
                echo "❌ Ошибка скачивания установщика Hysteria2."
            fi
            shopt -s nullglob
            HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json)
            shopt -u nullglob
        else
            echo "Пропускаем установку Hysteria2..."
        fi
    else
        if curl -sfLo /root/hysteria-install.sh https://raw.githubusercontent.com/NedgNDG/hysteria2-install/main/hysteria-install.sh; then
            chmod +x /root/hysteria-install.sh
            bash /root/hysteria-install.sh
        else
            echo "❌ Ошибка скачивания установщика Hysteria2."
        fi
        shopt -s nullglob
        HYS_CONFS=(/etc/hysteria/*.yaml /etc/hysteria/*.json)
        shopt -u nullglob
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

    if [[ -z "$TARGET_PORT" ]]; then
        read -p "Не удалось найти порт. Введи целевой порт вручную: " TARGET_PORT
    else
        echo "Порт определен: $TARGET_PORT"
    fi
elif [[ "$port_setup_choice" == "2" ]]; then
    echo ""
    echo "[6/9] Установка и поиск порта AmneziaWG..."
    shopt -s nullglob
    AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf)
    shopt -u nullglob

    if [ ${#AWG_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации AmneziaWG."
        read -p "Хочешь запустить установщик AmneziaWG? (выбери N, если AWG уже настроен) [y/N]: " run_awg
        if [[ "$run_awg" =~ ^[Yy]$ ]]; then
            if curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; then
                chmod +x /root/amneziawg-install.sh
                bash /root/amneziawg-install.sh
            else
                echo "❌ Ошибка скачивания установщика AmneziaWG."
            fi
            shopt -s nullglob
            AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf)
            shopt -u nullglob
        else
            echo "Пропускаем установку AmneziaWG..."
        fi
    else
        if curl -sfLo /root/amneziawg-install.sh https://raw.githubusercontent.com/wiresock/amneziawg-install/main/amneziawg-install.sh; then
            chmod +x /root/amneziawg-install.sh
            bash /root/amneziawg-install.sh
        else
            echo "❌ Ошибка скачивания установщика AmneziaWG."
        fi
        shopt -s nullglob
        AWG_CONFS=(/etc/amneziawg/*.conf /etc/amnezia/amneziawg/*.conf)
        shopt -u nullglob
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

    if [[ -z "$TARGET_PORT" ]]; then
        read -p "Не удалось найти порт. Введи целевой порт вручную: " TARGET_PORT
    else
        echo "Порт определен: $TARGET_PORT"
    fi
else
    echo ""
    echo "[6/9] Установка и поиск порта WireGuard..."
    shopt -s nullglob
    WG_CONFS=(/etc/wireguard/*.conf)
    shopt -u nullglob

    if [ ${#WG_CONFS[@]} -gt 0 ]; then
        echo "Найдены существующие конфигурации WireGuard."
        read -p "Хочешь запустить установщик WireGuard? (выбери N, если WG уже настроен) [y/N]: " run_wg
        if [[ "$run_wg" =~ ^[Yy]$ ]]; then
            if curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; then
                chmod +x /root/wireguard-install.sh
                bash /root/wireguard-install.sh
            else
                echo "❌ Ошибка скачивания установщика WireGuard."
            fi
            shopt -s nullglob
            WG_CONFS=(/etc/wireguard/*.conf)
            shopt -u nullglob
        else
            echo "Пропускаем установку WireGuard..."
        fi
    else
        if curl -sfLo /root/wireguard-install.sh https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh; then
            chmod +x /root/wireguard-install.sh
            bash /root/wireguard-install.sh
        else
            echo "❌ Ошибка скачивания установщика WireGuard."
        fi
        shopt -s nullglob
        WG_CONFS=(/etc/wireguard/*.conf)
        shopt -u nullglob
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

    if [[ -z "$TARGET_PORT" ]]; then
        read -p "Не удалось найти порт. Введи целевой порт вручную: " TARGET_PORT
    else
        echo "Порт определен: $TARGET_PORT"
    fi
fi

echo "$TARGET_PORT" > /root/.vk-proxy-target-port

# 6. Скачивание ядра
echo ""
if [[ "$PROXY_REPO" == "Custom_Direct_Link" ]]; then
    echo "[7/9] Загрузка ядра по прямой ссылке..."
    if ! wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
        echo "❌ Ошибка: Не удалось скачать ядро по прямой ссылке."
        exit 1
    fi
    chmod +x /root/server-linux-$SYS_ARCH
    echo "$LATEST_TAG" > /root/.vk-proxy-version
    echo "Прямая ссылка" > /root/.vk-proxy-repo
    PROXY_REPO="Прямая ссылка"
else
    echo "[7/9] Загрузка ядра ($SYS_ARCH) из репозитория $PROXY_REPO..."
    echo "$PROXY_REPO" > /root/.vk-proxy-repo
    API_URL="https://api.github.com/repos/${PROXY_REPO}/releases/latest"
    API_RESP=$(curl -s --connect-timeout 10 "$API_URL")
    LATEST_TAG=$(echo "$API_RESP" | jq -r ".tag_name")
    DOWNLOAD_URL=""

    if [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "turn-proxy-server") | .browser_download_url' | head -n 1)
    else
        DOWNLOAD_URL=$(echo "$API_RESP" | jq -r '.assets[] | select(.name == "server-linux-'"${SYS_ARCH}"'") | .browser_download_url' | head -n 1)
    fi

    if [[ "$DOWNLOAD_URL" == "null" || -z "$DOWNLOAD_URL" ]]; then
        echo "❌ Ошибка: В репозитории $PROXY_REPO не найдено релизов для $SYS_ARCH."
        exit 1
    fi

    if ! wget -q --show-progress -O /root/server-linux-$SYS_ARCH "$DOWNLOAD_URL"; then
        echo "❌ Ошибка: Не удалось скачать ядро прокси. Проверьте интернет или лимиты GitHub API."
        exit 1
    fi
    chmod +x /root/server-linux-$SYS_ARCH
    echo "$LATEST_TAG" > /root/.vk-proxy-version
fi

# 7. Выбор кастомных аргументов запуска
echo ""
echo "[8/9] Настройка аргументов запуска..."
if [[ -f /root/.vk-proxy-core-type ]] && [[ "$(cat /root/.vk-proxy-core-type)" == "custom" ]]; then
    echo -e "Для вашего ядра выбран ручной режим (Raw)."
    echo "Введи аргументы (например: -listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless)"
    read -p "Аргументы: " custom_args
    if [[ -n "$custom_args" ]]; then
        echo "$custom_args" > /root/.vk-proxy-custom-args
        echo "Сохранены кастомные аргументы!"
    else
        echo "go" > /root/.vk-proxy-core-type
        echo "⚠️ Аргументы не введены. Использован стандартный Go-пресет."
    fi
else
    read -p "Хочешь прописать кастомные аргументы запуска вручную (отменить автоматику)? [y/N]: " use_custom_args
    if [[ "$use_custom_args" =~ ^[Yy]$ ]]; then
        echo "Введи аргументы (например: -listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT -vless)"
        read -p "Аргументы: " custom_args
        if [[ -n "$custom_args" ]]; then
            echo "$custom_args" > /root/.vk-proxy-custom-args
            echo "Сохранены кастомные аргументы!"
        fi
    else
        rm -f /root/.vk-proxy-custom-args
    fi
fi

# 8. Служба и Фаервол
echo ""
echo "[9/9] Настройка службы и фаервола..."
systemctl stop vk-proxy 2>/dev/null || true

# Формируем итоговые параметры для systemd
if [[ -f /root/.vk-proxy-custom-args ]] && [[ -n "$(cat /root/.vk-proxy-custom-args)" ]]; then
    EXEC_ARGS=$(cat /root/.vk-proxy-custom-args)
else
    if [[ -f /root/.vk-proxy-vless ]] && [[ "$(cat /root/.vk-proxy-vless)" == "1" ]]; then VLESS_FLAG=" -vless"; else VLESS_FLAG=""; fi
    
    DC_FLAG=""
    if [[ -f /root/.vk-proxy-dc-mode ]] && [[ "$(cat /root/.vk-proxy-dc-mode)" == "1" ]]; then
        if [[ -f /root/.vk-proxy-jazz-room ]]; then
            DC_FLAG=" -jazz-room $(cat /root/.vk-proxy-jazz-room) -dc"
        elif [[ -f /root/.vk-proxy-yandex-link ]]; then
            DC_FLAG=" -yandex-link $(cat /root/.vk-proxy-yandex-link) -dc"
        fi
    fi

    CORE_TYPE="go"
    if [[ -f /root/.vk-proxy-core-type ]]; then
        CORE_TYPE=$(cat /root/.vk-proxy-core-type)
    elif [[ "$PROXY_REPO" == *"Urtyom-Alyanov"* ]]; then
        CORE_TYPE="rust"
    fi

    if [[ "$CORE_TYPE" == "rust" ]]; then
        EXEC_ARGS="-N -l 0.0.0.0:$PROXY_PORT -p 127.0.0.1:$TARGET_PORT -n 10000$DC_FLAG$VLESS_FLAG"
    else
        EXEC_ARGS="-listen 0.0.0.0:$PROXY_PORT -connect 127.0.0.1:$TARGET_PORT$DC_FLAG$VLESS_FLAG"
    fi
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

if command -v ufw &> /dev/null; then
    echo "Открываем порт $PROXY_PORT в UFW..."
    ufw allow $PROXY_PORT/tcp > /dev/null 2>&1
    ufw allow $PROXY_PORT/udp > /dev/null 2>&1
fi

# 9. Панель
echo ""
echo "[+] Создание консольной панели (vk-panel)..."
create_panel

echo ""
echo "==================================================="
echo "✅ Установка полностью завершена!"
echo "Трафик прокси направляется на локальный порт: $TARGET_PORT"
echo "Внешний порт прокси для подключения: $PROXY_PORT"
echo "==================================================="
echo "⚠️  ВАЖНО ДЛЯ ОБЛАКОВ (Oracle, AWS, Yandex и др.):"
echo "Обязательно открой порт $PROXY_PORT (TCP/UDP) в панели"
echo "управления сервером на сайте твоего хостинг-провайдера!"
echo "==================================================="
echo "🔥 Для вызова панели управления просто напиши:"
echo "vk-panel"
echo "==================================================="
