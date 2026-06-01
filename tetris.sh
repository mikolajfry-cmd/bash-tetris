#!/usr/bin/env bash

# ==============================================================================
#  PRO TETRIS IN BASH - BARDZO ROZBUDOWANA WERSJA ULTRA-FLUID
# ==============================================================================
#  Sterowanie: W (Obrót), A (Lewo), S (Szybciej w dół), D (Prawo)
#              R (Natychmiastowy zrzut / Hard Drop)
#              Q (Wyjście)
# ==============================================================================

# Ukrycie kursora i czyszczenie na starcie
trap 'cleanup' EXIT
tput civis
stty -icanon -echo

# --- KONFIGURACJA I ZMIENNE GLOBALNE ---
BOARD_ROWS=20
BOARD_COLS=10

# Kolory ANSI (Tła)
COLOR_NONE="\e[0m"
COLOR_BORDER="\e[48;5;239m  \e[0m"
COLOR_GHOST="\e[48;5;236m░░\e[0m"

# Definicje kolorów dla 7 klocków (Tetrominoes)
COLOR_I="\e[48;5;39m  \e[0m"   # Cyjan
COLOR_O="\e[48;5;220m  \e[0m"  # Żółty
COLOR_T="\e[48;5;135m  \e[0m"  # Fiolet
COLOR_S="\e[48;5;82m  \e[0m"   # Zielony
COLOR_Z="\e[48;5;196m  \e[0m"  # Czerwony
COLOR_J="\e[48;5;27m  \e[0m"   # Niebieski
COLOR_L="\e[48;5;208m  \e[0m"  # Pomarańczowy

# Tablica kolorów przypisana do ID klocka
declare -A KLOCKI_KOLORY
KLOCKI_KOLORY[1]=$COLOR_I
KLOCKI_KOLORY[2]=$COLOR_O
KLOCKI_KOLORY[3]=$COLOR_T
KLOCKI_KOLORY[4]=$COLOR_S
KLOCKI_KOLORY[5]=$COLOR_Z
KLOCKI_KOLORY[6]=$COLOR_J
KLOCKI_KOLORY[7]=$COLOR_L

# Definicje kształtów w postaci spłaszczonych macierzy 4x4 (0-puste, X-blok)
SHAPE_I="0000XXXX00000000"
SHAPE_O="00000XX00XX00000"
SHAPE_T="0X00XXX000000000"
SHAPE_S="0XX0XX0000000000"
SHAPE_Z="XX000XX000000000"
SHAPE_J="X000XXX000000000"
SHAPE_L="00X0XXX000000000"

declare -A SHAPES
SHAPES[1]=$SHAPE_I
SHAPES[2]=$SHAPE_O
SHAPES[3]=$SHAPE_T
SHAPES[4]=$SHAPE_S
SHAPES[5]=$SHAPE_Z
SHAPES[6]=$SHAPE_J
SHAPES[7]=$SHAPE_L

# Inicjalizacja pustej planszy (0 = puste miejsce)
declare -A BOARD
init_board() {
    for ((r=0; r<BOARD_ROWS; r++)); do
        for ((c=0; c<BOARD_COLS; c++)); do
            BOARD[$r,$c]=0
        done
    done
}

# Statystyki gry
SCORE=0
LINES_CLEARED=0
LEVEL=1
GAME_OVER=0
TICK_COUNT=0
SPEED_DELAY=20 # Im mniejsze, tym szybciej (kontroluje interwał grawitacji)

# Statystyki klocków
declare -A PIECE_STATS
for i in {1..7}; do PIECE_STATS[$i]=0; done

# --- EKRAN STARTOWY ---
show_intro() {
    echo -e "\e[H\e[J"
    echo -e "\e[1;31m  _____  ______  _______  _____   _____  _____\e[0m"
    echo -e "\e[1;33m |_   _||  ____|__   __||  __ \ |_   _|/ ____|\e[0m"
    echo -e "\e[1;32m   | |  | |__     | |   | |__) |  | | | (___  \e[0m"
    echo -e "\e[1;36m   | |  |  __|    | |   |  _  /   | |  \___ \ \e[0m"
    echo -e "\e[1;34m   | |  | |____   | |   | | \ \  _| |_ ____) |\e[0m"
    echo -e "\e[1;35m   |_|  |______|  |_|   |_|  \_\|_____|_____/ \e[0m"
    echo -e "\e[0m"
    echo -e " ================================================"
    echo -e "             \e[1;5;37mNACISNIJ [ENTER] ABY ZACZAC\e[0m"
    echo -e " ================================================"
    echo -e "  Sterowanie:"
    echo -e "  [ A ] - Lewo        [ D ] - Prawo"
    echo -e "  [ W ] - Obrot       [ S ] - Przyspiesz"
    echo -e "  [ R ] - HARD DROP   [ Q ] - Wyjscie"
    echo -e " ------------------------------------------------"
    read -r
}

cleanup() {
    tput cnorm
    stty echo icanon
    echo -e "\e[?25h\e[0m"
}

# Losowanie nowego klocka
get_random_piece() {
    echo $((1 + RANDOM % 7))
}

# Inicjalizacja pozycji klocka
spawn_piece() {
    CURRENT_PIECE=$NEXT_PIECE
    NEXT_PIECE=$(get_random_piece)

    # Pozycja startowa (środek góry planszy)
    PIECE_Y=-1
    PIECE_X=3
    PIECE_ROT=0 # 0, 1, 2, 3 (obroty o 90 stopni)

    ((PIECE_STATS[$CURRENT_PIECE]++))

    # Sprawdzenie kolizji na wejściu -> Game Over
    if check_collision $PIECE_Y $PIECE_X $PIECE_ROT; then
        GAME_OVER=1
    fi
}

# --- LOGIKA ROTACJI I MACIERZY ---
# Pobiera wartość z matrycy 4x4 uwzględniając obrót
get_shape_cell() {
    local id=$1
    local rot=$2
    local r=$3
    local c=$4
    local str=${SHAPES[$id]}

    local orig_r=$r
    local orig_c=$c

    # Przeliczanie indeksów dla odpowiedniego obrotu
    case $rot in
        1) # 90 stopni w prawo
            orig_r=$((3 - c))
            orig_c=$r
            ;;
        2) # 180 stopni
            orig_r=$((3 - r))
            orig_c=$((3 - c))
            ;;
        3) # 270 stopni
            orig_r=$c
            orig_c=$((3 - r))
            ;;
    esac

    local idx=$((orig_r * 4 + orig_c))
    if [[ ${str:$idx:1} == "X" ]]; then
        echo 1
    else
        echo 0
    fi
}

# Sprawdzanie kolizji klocka z granicami planszy lub zablokowanymi elementami
check_collision() {
    local py=$1
    local px=$2
    local prot=$3

    for ((r=0; r<4; r++)); do
        for ((c=0; c<4; c++)); do
            if [[ $(get_shape_cell $CURRENT_PIECE $prot $r $c) -eq 1 ]]; then
                local board_r=$((py + r))
                local board_c=$((px + c))

                # Jeśli wychodzi poza boki lub dno planszy
                if (( board_c < 0 || board_c >= BOARD_COLS || board_r >= BOARD_ROWS )); then
                    return 0 # Kolizja występuje
                fi

                # Jeśli dotyka zablokowanego klocka na planszy
                if (( board_r >= 0 )); then
                    if [[ ${BOARD[$board_r,$board_c]} -ne 0 ]]; then
                        return 0
                    fi
                fi
            fi
        done
    done
    return 1 # Brak kolizji
}

# --- MECHANIKA ROZGRYWKI ---
move_left() {
    if ! check_collision $PIECE_Y $((PIECE_X - 1)) $PIECE_ROT; then
        ((PIECE_X--))
    fi
}

move_right() {
    if ! check_collision $PIECE_Y $((PIECE_X + 1)) $PIECE_ROT; then
        ((PIECE_X++))
    fi
}

rotate() {
    local next_rot=$(( (PIECE_ROT + 1) % 4 ))
    if ! check_collision $PIECE_Y $PIECE_X $next_rot; then
        PIECE_ROT=$next_rot
    # System Wall-Kick (podstawowy): spróbuj przesunąć w lewo lub prawo przy ścianie
    elif ! check_collision $PIECE_Y $((PIECE_X - 1)) $next_rot; then
        ((PIECE_X--))
        PIECE_ROT=$next_rot
    elif ! check_collision $PIECE_Y $((PIECE_X + 1)) $next_rot; then
        ((PIECE_X++))
        PIECE_ROT=$next_rot
    fi
}

# Funkcja grawitacji (krok w dół)
move_down() {
    if ! check_collision $((PIECE_Y + 1)) $PIECE_X $PIECE_ROT; then
        ((PIECE_Y++))
        return 0
    else
        lock_piece
        check_lines
        spawn_piece
        return 1
    fi
}

# Szybki zrzut klocka na sam dół (Hard Drop pod 'R')
hard_drop() {
    while ! check_collision $((PIECE_Y + 1)) $PIECE_X $PIECE_ROT; do
        ((PIECE_Y++))
        ((SCORE += 2))
    done
    lock_piece
    check_lines
    spawn_piece
}

# Obliczanie pozycji cienia klocka (Ghost Piece)
get_ghost_y() {
    local gy=$PIECE_Y
    while ! check_collision $((gy + 1)) $PIECE_X $PIECE_ROT; do
        ((gy++))
    done
    echo $gy
}

# Zablokowanie klocka na planszy po upadku
lock_piece() {
    for ((r=0; r<4; r++)); do
        for ((c=0; c<4; c++)); do
            if [[ $(get_shape_cell $CURRENT_PIECE $PIECE_ROT $r $c) -eq 1 ]]; then
                local board_r=$((PIECE_Y + r))
                local board_c=$((PIECE_X + c))
                if (( board_r >= 0 )); then
                    BOARD[$board_r,$board_c]=$CURRENT_PIECE
                fi
            fi
        done
    done
}

# Sprawdzanie i usuwanie pełnych linii
check_lines() {
    local lines_found=0
    for ((r=BOARD_ROWS-1; r>=0; r--)); do
        local is_full=1
        for ((c=0; c<BOARD_COLS; c++)); do
            if [[ ${BOARD[$r,$c]} -eq 0 ]]; then
                is_full=0
                break
            fi
        done

        if [[ $is_full -eq 1 ]]; then
            ((lines_found++))
            # Przesunięcie wszystkich linii powyżej w dół
            for ((k=r; k>0; k--)); do
                for ((c=0; c<BOARD_COLS; c++)); do
                    BOARD[$k,$c]=${BOARD[$((k-1)),$c]}
                done
            done
            # Wyczyszczenie najwyższej linii
            for ((c=0; c<BOARD_COLS; c++)); do
                BOARD[0,c]=0
            done
            ((r++)) # Sprawdź ten sam indeks linii ponownie
        fi
    done

    if (( lines_found > 0 )); then
        ((LINES_CLEARED += lines_found))
        # Naliczanie punktów w stylu retro maszyn
        case $lines_found in
            1) ((SCORE += 100 * LEVEL)) ;;
            2) ((SCORE += 300 * LEVEL)) ;;
            3) ((SCORE += 500 * LEVEL)) ;;
            4) ((SCORE += 800 * LEVEL)) ;; # TETRIS!
        esac

        # Zmiana poziomu co 10 linii
        LEVEL=$(( (LINES_CLEARED / 10) + 1 ))
        # Przyspieszenie gry wraz z poziomem
        SPEED_DELAY=$(( 20 - LEVEL ))
        (( SPEED_DELAY < 2 )) && SPEED_DELAY=2
    fi
}

# --- BUFFERED RENDER ENGINE (Brak migotania) ---
render_game() {
    local out=""
    # Przeniesienie kursora na pozycję 0,0 zamiast clear
    out+="\e[H"

    out+="\e[1;36m  --- TETRIS BASH PRO --- \e[0m\n\n"

    # Przygotowanie wirtualnego podglądu planszy aktywnego klocka i cienia
    local ghost_y=$(get_ghost_y)
    declare -A VIEW_BOARD

    for ((r=0; r<BOARD_ROWS; r++)); do
        for ((c=0; c<BOARD_COLS; c++)); do
            VIEW_BOARD[$r,$c]=${BOARD[$r,$c]}
        done
    done

    # Nałożenie cienia (Ghost Block) na podgląd renderowania
    for ((r=0; r<4; r++)); do
        for ((c=0; c<4; c++)); do
            if [[ $(get_shape_cell $CURRENT_PIECE $PIECE_ROT $r $c) -eq 1 ]]; then
                local gy=$((ghost_y + r))
                local gc=$((PIECE_X + c))
                if (( gy >= 0 && gy < BOARD_ROWS && gc >= 0 && gc < BOARD_COLS )); then
                    if [[ ${VIEW_BOARD[$gy,$gc]} -eq 0 ]]; then
                        VIEW_BOARD[$gy,$gc]="G"
                    fi
                fi
            fi
        done
    done

    # Nałożenie żywego, aktywnego klocka na podgląd renderowania
    for ((r=0; r<4; r++)); do
        for ((c=0; c<4; c++)); do
            if [[ $(get_shape_cell $CURRENT_PIECE $PIECE_ROT $r $c) -eq 1 ]]; then
                local br=$((PIECE_Y + r))
                local bc=$((PIECE_X + c))
                if (( br >= 0 && br < BOARD_ROWS && bc >= 0 && bc < BOARD_COLS )); then
                    VIEW_BOARD[$br,$bc]=$CURRENT_PIECE
                fi
            fi
        done
    done

    # RENDEROWANIE PANELU BOCZNEGO I PLANSZY GLOWNEJ
    # Górna belka
    out+="  ${COLOR_BORDER}"
    for ((c=0; c<BOARD_COLS; c++)); do out+="${COLOR_BORDER}"; done
    out+="${COLOR_BORDER}    STATS & NEXT\n"

    for ((r=0; r<BOARD_ROWS; r++)); do
        out+="  ${COLOR_BORDER}" # Lewa ramka
        for ((c=0; c<BOARD_COLS; c++)); do
            local cell=${VIEW_BOARD[$r,$c]}
            if [[ $cell == "0" ]]; then
                out+="  " # Puste pole
            elif [[ $cell == "G" ]]; then
                out+="${COLOR_GHOST}" # Cień klocka
            else
                out+="${KLOCKI_KOLORY[$cell]}" # Kolorowy zablokowany/aktywny klocek
            fi
        done
        out+="${COLOR_BORDER}" # Prawa ramka

        # Logika wyświetlania danych w bocznej sekcji (HUD)
        case $r in
            1) out+="    SCORE: \e[1;32m${SCORE}\e[0m" ;;
            2) out+="    LINES: \e[1;33m${LINES_CLEARED}\e[0m" ;;
            3) out+="    LEVEL: \e[1;35m${LEVEL}\e[0m" ;;
            5) out+="    NEXT PIECE:" ;;
            6|7|8|9)
                local nr=$((r - 6))
                out+="    "
                for ((nc=0; nc<4; nc++)); do
                    if [[ $(get_shape_cell $NEXT_PIECE 0 $nr $nc) -eq 1 ]]; then
                        out+="${KLOCKI_KOLORY[$NEXT_PIECE]}"
                    else
                        out+="  "
                    fi
                done
                ;;
            12) out+="    CONTROLS:" ;;
            13) out+="    [A][S][D] - Ruch" ;;
            14) out+="    [W]       - Obrot" ;;
            15) out+="    [R]       - Hard Drop" ;;
            16) out+="    [Q]       - Wyjscie" ;;
        esac
        out+="\n"
    done

    # Dolna belka planszy
    out+="  ${COLOR_BORDER}"
    for ((c=0; c<BOARD_COLS; c++)); do out+="${COLOR_BORDER}"; done
    out+="${COLOR_BORDER}\n"

    # Wypchnięcie całego bufora na ekran naraz
    echo -ne "$out"
}

# --- GLOWNA PETLA GRY ---
init_board
show_intro
NEXT_PIECE=$(get_random_piece)
spawn_piece

while [[ $GAME_OVER -eq 0 ]]; do
    render_game

    # Nieblokujący odczyt klawiszy (timeout ustawiony na ultra niski dla płynności)
    if read -s -n 1 -t 0.02 key; then
        case $key in
            [aA]) move_left ;;
            [dD]) move_right ;;
            [wW]) rotate ;;
            [sS]) move_down ;; # Przyspieszenie wymuszone przyciskiem S
            [rR]) hard_drop ;; # Natychmiastowy zrzut w dół
            [qQ]) GAME_OVER=1 ;;
        esac
    fi

    # Licznik cykli procesora gry sterujący grawitacją klocka
    ((TICK_COUNT++))
    if (( TICK_COUNT >= SPEED_DELAY )); then
        move_down
        TICK_COUNT=0
    fi
done

# --- KONIEC GRY ---
cleanup
echo -e "\n\e[1;31m ========================================"
echo -e "               GAME OVER!                "
echo -e " ========================================"
echo -e "  Twoj koncowy wynik: \e[1;32m${SCORE}\e[1;31m"
echo -e "  Czyszczone linie:   \e[1;33m${LINES_CLEARED}\e[1;31m"
echo -e "  Osiagniety poziom:  \e[1;35m${LEVEL}\e[1;31m"
echo -e " ========================================\e[0m\n"
