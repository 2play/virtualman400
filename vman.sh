#!/bin/bash

# START-UP ---------------------------------------------------------------------

function waitForAnyKey() {
    read -n 1 -s -r -p " < press any key > "
    echo
}

# require user pi
if [[ $USER != "pi" ]]; then
    echo "ERROR - script must be run as user pi"
    waitForAnyKey
    exit 1
fi

# if not in the right place, move and re-execute
dir="/home/pi/vman"
path="$dir/vman.sh"
function checkLocation() {
    local pathActual="$(cd `dirname "$0"` && pwd)/$(basename "$BASH_SOURCE")"
    if [[ "$pathActual" != "$path" ]]; then
        mkdir -p "$dir"
        mv "$pathActual" "$path"
        exec "$path"
    fi
}
checkLocation

# if not owned by pi, reset and re-execute
if [[ $(stat -c "%U %G" "$path") != "pi pi" ]]; then
    sudo chown pi.pi "$path"
    exec "$path"
fi

# require connection
if ! nc -dzw1 8.8.4.4 443; then
    echo "ERROR - Internet connection required"
    waitForAnyKey
    exit 1
fi

# check repo
function checkRepo() {
    local repo hash
    repo="https://github.com/willy-electrix/virtualman400.git"
    hash=$(sha1sum "$path")
    cd "$dir"
    if [[ "$(git remote -v)" == *"$repo (fetch)"* ]]; then
        # get latest, and if script has changed, re-execute
        git fetch --all
        git reset --hard origin/master
        if [[ "$hash" != "$(sha1sum "$path")" ]]; then
            exec "$path"
        fi
    else
        # repo problem, start the repo fresh, then re-execute
        rm -rf .git
        git init
        git remote add origin "$repo"
        exec "$path"
    fi
}
checkRepo
unset path dir

# at this point, we're definitely loading the menu...

# FUNCTIONS --------------------------------------------------------------------

function init() {
    h1="VirtualMan Post-Fixes"

    h2Main="| Post-Fixes & Tools |"
    h2Toggle="| Toggle Fix Inclusion |"
    h2Force="| Force Apply Fixes |"
    h2Tools="| Tools & More |"

         h3Main=" "
       h3Toggle="   Doesn't disable fixes already applied!"
        h3Force=" "
        h3Tools=" "
       h3MainOk="            You are up-to-date !"
    h3MainApply="         There are fixes to apply !"
      h3MainOff="   You are up-to-date; some fixes ignored."

    statusOk="\e[92mup-to-date\e[39m"
    statusApply="\e[93mto be applied\e[39m"
    statusOff="\e[91mwill NOT apply\e[39m"

    toggleOff="OFF"
    toggleOn="ON "

    idxName=0
    idxNameFull=1
    idxVer=2
    idxVerLocal=3
    idxToggle=4
    idxStatus=5

    fixes=(
        "options"     "Options Menu" "1" "" "" ""
        "nes"         "NES Clean-up" "1" "" "" ""
        "party"       "Mario Party"  "1" "" "" ""
        "games"       "Game Lists"   "1" "" "" ""
        "collections" "Collections"  "1" "" "" ""
        "configs"     "Config Files" "1" "" "" ""
        #"intros"      "Intro Videos" "0" "" "" ""
        #"slides"      "Screensaver"  "0" "" "" ""
        #"bgm"         "BG Music"     "0" "" "" ""
    )
    fixesSize=${#fixes[@]}
    fixesSizeOne=6
    fixesCount=$((fixesSize/fixesSizeOne))

    reboot="false"

    dialogHeight=17
    dialogWidth=50
    dialogHeightInner=9

    dir="/home/pi/.vman"
    mkdir -p "$dir/nes"
    mkdir -p "$dir/off"
    mkdir -p "$dir/options"
    mkdir -p "$dir/tmp"
    mkdir -p "$dir/ver"
}

function showMainMenu() {
    local options cancelLabel choice
    options=(
        S "Status"
        A "Apply New Fixes"
        I "Toggle Fix Inclusion"
        F "Force Apply Fixes"
        T "Tools & More"
    )
    while true; do
        checkFixes
        if [[ "$reboot" == "true" ]]; then
            cancelLabel="Reboot"
        else
            cancelLabel="Exit"
        fi
        choice=$(dialog \
            --backtitle "$h1" \
            --title "$h2Main" \
            --ok-label OK \
            --cancel-label "$cancelLabel" \
            --menu "$h3Main" \
            $dialogHeight $dialogWidth $dialogHeightInner \
            "${options[@]}" \
            2>&1 > /dev/tty)
        case $choice in
            S) showStatus ;;
            A) applyFixes ;;
            I) showToggleMenu ;;
            F) showForceMenu ;;
            T) showToolsMenu ;;
            *) break ;;
        esac
    done
    if [[ "$reboot" == "true" ]]; then
        sudo killall emulationstation
        sudo reboot
        declare -p
        exit 0
    fi
}

function showToggleMenu() {
    local options fix choice path
    while true; do
        options=()
        for ((fix=0; fix<$fixesCount; fix++)); do
            options+=($((fix+1)) "${fixes[fix*fixesSizeOne+idxToggle]} > ${fixes[fix*fixesSizeOne+idxNameFull]}")
        done
        choice=$(dialog \
            --backtitle "$h1" \
            --title "$h2Toggle" \
            --ok-label OK \
            --cancel-label Back \
            --menu "$h3Toggle" \
            $dialogHeight $dialogWidth $dialogHeightInner \
            "${options[@]}" \
            2>&1 > /dev/tty)
        if [[ $choice == "" ]]; then
            break;
        fi
        fix=$((choice-1))
        path="$dir/off/${fixes[fix*fixesSizeOne+idxName]}"
        if [[ -f "$path" ]]; then
            rm "$path"
            fixes[fix*fixesSizeOne+idxToggle]="$toggleOn"
        else
            touch "$path"
            fixes[fix*fixesSizeOne+idxToggle]="$toggleOff"
        fi
    done
}

function showForceMenu() {
    local options fix choice
    options=()
    for ((fix=0; fix<$fixesCount; fix++)); do
        options+=($((fix+1)) "${fixes[fix*fixesSizeOne+idxNameFull]}")
    done
    while true; do
        choice=$(dialog \
            --backtitle "$h1" \
            --title "$h2Force" \
            --ok-label OK \
            --cancel-label Back \
            --menu "$h3Force" \
            $dialogHeight $dialogWidth $dialogHeightInner \
            "${options[@]}" \
            2>&1 > /dev/tty)
        if [[ "$choice" == "" ]]; then
            break;
        fi
        applyFix "$((choice-1))"
    done
}

function showToolsMenu() {
    local options choice
    options=(
        1 "Get Daphne DAT Files"
        2 "Clear Daphne DAT Files"
        3 "Reset All Configs & Lists"
    )
    while true; do
        choice=$(dialog \
            --backtitle "$h1" \
            --title "$h2Tools" \
            --ok-label OK \
            --cancel-label Back \
            --menu "$h3Tools" \
            $dialogHeight $dialogWidth $dialogHeightInner \
            "${options[@]}" \
            2>&1 > /dev/tty)
        case $choice in
            1) getDaphneDats ;;
            2) clearDaphneDats ;;
            3) resetConfigFiles ;;
            *) break ;;
        esac
    done
}

function checkFixes() {
    local fixIdx countApply countOff verPath verLocal toggle status
    countApply=0
    countOff=0
    for ((fixIdx=0; fixIdx<$fixesSize; fixIdx+=fixesSizeOne)); do
        verPath="$dir/ver/${fixes[fixIdx+idxName]}"
        verLocal="0"
        toggle=$toggleOn
        if [[ -f "$verPath" ]]; then
            verLocal=$(<$verPath)
        fi
        if [[ -f "$dir/off/${fixes[fixIdx+idxName]}" ]]; then
            toggle=$toggleOff
        fi
        if [[ "${fixes[fixIdx+idxVer]}" == "$verLocal" ]]; then
            status=$statusOk
        else
            if [[ "$toggle" == "$toggleOn" ]]; then
                status=$statusApply
                ((countApply++))
            else
                status=$statusOff
                ((countOff++))
            fi
        fi
        fixes[fixIdx+idxVerLocal]=$verLocal
        fixes[fixIdx+idxToggle]=$toggle
        fixes[fixIdx+idxStatus]=$status
    done
    if [[ $countApply == 0 ]]; then
        if [[ $countOff == 0 ]]; then
            h3Main=$h3MainOk
        else
            h3Main=$h3MainOff
        fi
    else
        h3Main=$h3MainApply
    fi
}

function showStatus() {
    local fixIdx
    clear
    printf "\n\n"
    printf "Fix\t\tVer. Applied\tVer. Available\tStatus\n\n"
    printf "\e[2m===============\t===============\t===============\t===============\e[22m\n\n"

    for ((fixIdx=0; fixIdx<$fixesSize; fixIdx+=fixesSizeOne)); do
        printf "${fixes[fixIdx+idxNameFull]}\t${fixes[fixIdx+idxVerLocal]}\t\t"
        printf "${fixes[fixIdx+idxVer]}\t\t${fixes[fixIdx+idxStatus]}\n\n"
    done
    printf "\e[2m===============\t===============\t===============\t===============\e[22m\n\n"
    printf "\n\n"
    waitForAnyKey
}

function applyFixes() {
    local fix
    for ((fix=0; fix<$fixesCount; fix++)); do
        if [[ "${fixes[fix*fixesSizeOne+idxStatus]}" == "$statusApply" ]]; then
            applyFix "$fix"
        fi
    done
}

function applyFix() {
    local choiceFound
    choiceFound="true"
    case $1 in
        0) fixOptions ;;
        1) fixNes ;;
        2) fixParty ;;
        3) fixGames ;;
        4) fixCollections ;;
        5) fixConfigs ;;
        *) choiceFound="false" ;;
    esac
    if [[ "$choiceFound" == "true" ]]; then
        printf "${fixes[$1*fixesSizeOne+idxVer]}" > "$dir/ver/${fixes[$1*fixesSizeOne+idxName]}"
        reboot="true"
    fi
}

function fixOptions() {
    local optionsDir
    optionsDir="$dir/options"

    cd ~
    if [[ ! -f "$optionsDir/hurstythemes.sh" ]]; then
        cp RetroPie/extras+/.pb-fixes/retropiemenu/Visuals/hurstythemes.sh "$optionsDir/"
        mv RetroPie/retropiemenu/Visuals/hurstythemes.sh "$optionsDir/"
        mv RetroPie/retropiemenu/hurstythemes.sh "$optionsDir/"
    fi
    rm RetroPie/retropiemenu/Visuals/hurstythemes.sh
    rm RetroPie/retropiemenu/hurstythemes.sh

    cd "$dir/tmp"
    rm -rf options
    git clone https://github.com/willy-electrix/virtualman400-options.git options

    cd options
    cp gamelist.xml /home/pi/RetroPie/extras+/.pb-fixes/retropie-gml/gamelist2play.xml
    cp gamelist.xml /opt/retropie/configs/all/emulationstation/gamelists/retropie/
    cp gamelist-uninstall.xml "$optionsDir/"
    cp hursty.sh /home/pi/RetroPie/retropiemenu/Visuals/
    cp virtualman.png /home/pi/RetroPie/retropiemenu/icons/
    cp virtualman.sh /home/pi/RetroPie/retropiemenu/

    cd ..
    rm -rf options
}

function fixNes() {
    cd /home/pi/RetroPie/roms/nes
    rm "Battle City (J).nes"
    rm tmnt2.zip
    mv samurai.zip "$dir/nes/"
    mv StreetFighterVI12.zip "$dir/nes/"
}

function fixParty() {
    local path
    path="/home/pi/RetroPie/roms/n64/Mario Party (USA).n64"

    if [[ "$(sha1sum "$path" | cut -c1-40)" != "579c48e211ae952530ffc8738709f078d5dd215e" ]]; then
        return 1
    fi

    cd "$dir/tmp"
    rm -rf fix02
    mkdir fix02
    cd fix02
    wget https://github.com/willy-electrix/virtualman400-misc/raw/master/fix02.dat
    unzip -P virtualman400 fix02.dat
    cat 07.dat 06.dat 05.dat 04.dat 03.dat 02.dat 01.dat 00.dat > merged.dat
    mv merged.dat "$path"
    cd ..
    rm -rf fix02
}

function fixGames() {
    cd /home/pi/RetroPie/roms
    rm -rf .git
    git init
    git remote add origin https://github.com/willy-electrix/virtualman400-games.git
    git fetch --all
    git reset --hard origin/master
    rm -rf .git
    rm .gitignore
    rm README.md
}

function fixCollections() {
    cd /opt/retropie/configs/all/emulationstation/collections
    rm -rf .git
    git init
    git remote add origin https://github.com/willy-electrix/virtualman400-collections.git
    git fetch --all
    git reset --hard origin/master
    rm -rf .git
    rm .gitignore
    rm README.md
}

function fixConfigs() {
    cd /
    rm -rf .git
    git init
    git remote add origin https://github.com/willy-electrix/virtualman400-configs.git
    git fetch --all
    git reset --hard origin/master
    rm -rf .git
    rm .gitignore
    rm README.md
}

function getDaphneDats() {
    printf "\n - getting Daphne .DAT files\n\n"

    cd /home/pi/RetroPie/roms/daphne
    rm -rf .git
    git init
    git remote add origin https://github.com/willy-electrix/virtualman400-daphne.git
    git fetch --all
    git reset --hard origin/master
    rm -rf .git
    rm .gitignore
    rm README.md

    printf "\n - done\n\n"
    waitForAnyKey
}

function clearDaphneDats() {
    printf "\n - clearing Daphne .DAT files\n\n"

    rm /home/pi/RetroPie/roms/daphne/*.daphne/*.dat

    printf "\n - done\n\n"
    waitForAnyKey
}

function resetConfigFiles() {
    printf "\n - last-resort config file reset (experimental)\n\n"

    read -p "   Are you sure? (y/n) " -n 1 -r
    printf "\n\n"
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi

    sudo killall emulationstation
    printf "   Here we go...\n\n"
    sleep 3

    cd /
    rm -rf .git
    git init
    git remote add origin https://github.com/willy-electrix/virtualman400-configs-original.git
    git fetch --all
    git reset --hard origin/master
    rm -rf .git
    rm .gitignore
    rm README.md

    applyFix 0
    applyFix 3
    applyFix 4
    applyFix 5

    printf "\n - done, rebooting..."
    sleep 3
    sudo reboot
}

# MAIN -------------------------------------------------------------------------

init && showMainMenu
