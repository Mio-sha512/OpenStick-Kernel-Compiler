#!/bin/bash
# Kernel Builder for OpenStick/postmarketOS

# Configuration and Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.build_config"
PATCHES_DIR="$SCRIPT_DIR/patches"
BUILDS_DIR="$SCRIPT_DIR/builds"
VENV_DIR="$SCRIPT_DIR/pmos-venv"
PMOS_WORKDIR="$SCRIPT_DIR/pmos-work"
PMBOOTSTRAP_DIR="$SCRIPT_DIR/pmbootstrap"
KERNEL_SRC_DIR="$SCRIPT_DIR/linux-msm8916"

# URLs
REPO_URL="https://github.com/msm8916-mainline/linux.git"
PMOS_CONFIG_URL="https://raw.githubusercontent.com/msm8916-mainline/linux/refs/heads/msm8916/6.17-rc6/kernel/configs/pmos.config"
DEFCONFIG_URL="https://gitlab.postmarketos.org/postmarketOS/pmaports/-/raw/master/device/testing/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64"
PMAPORTS_GIT="https://gitlab.postmarketos.org/postmarketOS/pmaports.git"

# Recommended Settings
REC_BRANCH="msm8916/6.12.1"
CPR_PATCH_NAME="cpr-6.12.1.patch"

# ANSI Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Enable aliases
shopt -s expand_aliases
set -e

# UI Functions

cleanup_ui() {
    tput cnorm; stty echo
}
trap cleanup_ui EXIT INT TERM

menu_select() {
    set +e
    local default_idx="$1"
    shift 1
    local options=("$@")
    local count=${#options[@]}
    local selected=$default_idx
    local start_idx=0
    local max_rows=10
    local term_width=$(tput cols)
    local row_count=0

    tput civis; stty -echo

    while true; do
        if [ $row_count -gt 0 ]; then tput cuu $row_count; fi
        row_count=0

        if [[ $selected -lt $start_idx ]]; then start_idx=$selected; fi
        if [[ $selected -ge $((start_idx + max_rows)) ]]; then start_idx=$((selected - max_rows + 1)); fi

        for ((i=0; i<max_rows; i++)); do
            idx=$((start_idx + i))
            if [[ $idx -ge $count ]]; then break; fi
            local item_text="${options[$idx]}"
            local max_w=$((term_width - 5))
            if [ ${#item_text} -gt $max_w ]; then item_text="${item_text:0:$((max_w-3))}..."; fi

            if [[ $idx -eq $selected ]]; then
                echo -e " ${GREEN}${BOLD}> $item_text${RESET}\033[K"
            else
                echo -e "   $item_text\033[K"
            fi
            ((row_count++))
        done

        echo -e "${YELLOW}   (Arrow Keys to Select)${RESET}\033[K"
        ((row_count++))

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            if [[ $key == "[A" ]]; then ((selected--)); [[ $selected -lt 0 ]] && selected=$((count - 1));
            elif [[ $key == "[B" ]]; then ((selected++)); [[ $selected -ge $count ]] && selected=0; fi
        elif [[ $key == "" ]]; then
            SELECTED_INDEX=$selected
            SELECTED_VALUE="${options[$selected]}"
            break
        fi
    done
    tput cnorm; stty echo; set -e
    echo ""
}

menu_multiselect() {
    set +e
    local title="$1"
    shift 1
    local options=("$@")
    local count=${#options[@]}
    local selected=0
    local start_idx=0
    local max_rows=10
    local row_count=0
    local -a selection_state
    for ((i=0; i<count; i++)); do selection_state[i]=0; done

    tput civis; stty -echo
    echo -e "${CYAN}${BOLD}$title${RESET}"

    while true; do
        if [ $row_count -gt 0 ]; then tput cuu $row_count; fi
        row_count=0

        if [[ $selected -lt $start_idx ]]; then start_idx=$selected; fi
        if [[ $selected -ge $((start_idx + max_rows)) ]]; then start_idx=$((selected - max_rows + 1)); fi

        for ((i=0; i<max_rows; i++)); do
            idx=$((start_idx + i))
            if [[ $idx -ge $count ]]; then break; fi
            local mark="[ ]"
            if [[ ${selection_state[$idx]} -eq 1 ]]; then mark="[${GREEN}x${RESET}]"; fi
            local item_text="${options[$idx]}"
            if [[ $idx -eq $selected ]]; then
                echo -e " ${GREEN}${BOLD}> $mark $item_text${RESET}\033[K"
            else
                echo -e "   $mark $item_text\033[K"
            fi
            ((row_count++))
        done

        echo -e "${YELLOW}   (Space: Toggle | Enter: Confirm)${RESET}\033[K"
        ((row_count++))

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            if [[ $key == "[A" ]]; then ((selected--)); [[ $selected -lt 0 ]] && selected=$((count - 1));
            elif [[ $key == "[B" ]]; then ((selected++)); [[ $selected -ge $count ]] && selected=0; fi
        elif [[ $key == " " ]]; then
            if [[ ${selection_state[$selected]} -eq 0 ]]; then selection_state[$selected]=1; else selection_state[$selected]=0; fi
        elif [[ $key == "" ]]; then break; fi
    done

    SELECTED_PATCHES=()
    for ((i=0; i<count; i++)); do
        if [[ ${selection_state[$i]} -eq 1 ]]; then SELECTED_PATCHES+=("${options[$i]}"); fi
    done
    tput cnorm; stty echo; set -e
    echo ""
}

log_info() { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_succ() { echo -e "${GREEN}[DONE]${RESET} $1"; }
log_err()  { echo -e "${RED}[ERR]${RESET} $1"; exit 1; }

# Init and args

INTERACTIVE=true
FORCE_CLEAN=false
KERNEL_VERSION="$REC_BRANCH"
ENABLE_CPR=false 
SAVE_CONFIG=false
declare -a CHOSEN_USER_PATCHES
USER_SPECIFIED_FLAGS=false

if [ -f "$CONFIG_FILE" ]; then source "$CONFIG_FILE"; fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --auto) INTERACTIVE=false ;;
        --clean) FORCE_CLEAN=true; USER_SPECIFIED_FLAGS=true ;;
        --version) KERNEL_VERSION="$2"; shift; USER_SPECIFIED_FLAGS=true ;;
        --cpr) ENABLE_CPR=true; USER_SPECIFIED_FLAGS=true ;;
        --no-cpr) ENABLE_CPR=false; USER_SPECIFIED_FLAGS=true ;;
        --save) SAVE_CONFIG=true; USER_SPECIFIED_FLAGS=true ;;
        *) log_warn "Unknown: $1" ;;
    esac
    shift
done

# If auto mode is requested, prefer saved config and do not prompt.
if [ "$INTERACTIVE" = false ]; then
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Auto mode: using saved settings from $CONFIG_FILE"
        source "$CONFIG_FILE"
        log_info "Settings: KERNEL_VERSION=$KERNEL_VERSION, ENABLE_CPR=$ENABLE_CPR"
    else
        if [ "$USER_SPECIFIED_FLAGS" = false ]; then
            log_err "Auto mode requested but no saved config at $CONFIG_FILE; run once interactively to create it or pass required flags (e.g., --version, --cpr)."
        else
            log_info "Auto mode: proceeding with explicitly provided flags."
        fi
    fi
fi

# Interactive configuration

if [ "$INTERACTIVE" = true ]; then
    clear
    echo -e "${GREEN}${BOLD}=== MSM8916 Kernel Builder ===${RESET}"
    echo ""

    # Step 1: Branch
    echo -e "${CYAN}${BOLD}Step 1: Select Kernel Version${RESET}"
    echo -e "${BLUE}Fetching branches...${RESET}"
    if command -v git &> /dev/null; then
        mapfile -t raw_branches < <(git ls-remote --heads "$REPO_URL" | \
            sed 's?.*refs/heads/??' | grep "msm8916/" | \
            grep -E "/v?[0-9]+\.[0-9]+" | grep -vE "android|cpr|backlight|panel" | sort -V -r)
        
        if [ ${#raw_branches[@]} -eq 0 ]; then
             read -p "Network failed. Enter branch manually [$KERNEL_VERSION]: " input
             KERNEL_VERSION="${input:-$KERNEL_VERSION}"
        else
            menu_options=()
            if [[ " ${raw_branches[*]} " =~ " ${REC_BRANCH} " ]]; then
                 menu_options+=("$REC_BRANCH  (RECOMMENDED)")
            fi
            menu_options+=("Manual Input")
            for branch in "${raw_branches[@]}"; do [[ "$branch" != "$REC_BRANCH" ]] && menu_options+=("$branch"); done
            menu_select "0" "${menu_options[@]}"
            val=$(echo "$SELECTED_VALUE" | awk '{print $1}')
            if [[ "$val" == "Manual" ]]; then read -p "Enter Branch Name: " KERNEL_VERSION; else KERNEL_VERSION="$val"; fi
        fi
    fi
    log_succ "Selected: $KERNEL_VERSION"
    echo ""

    # Step 2: CPR Patch
    echo -e "${CYAN}${BOLD}Step 2: CPU Performance (CPR)${RESET}"
    echo -e "CPR (Core Power Reduction) adjusts voltage to allow dynamic frequency scaling."
    echo -e "  - ${BOLD}Standard:${RESET} Fixed 998 MHz (Stable, Recommended)"
    echo -e "  - ${BOLD}CPR:${RESET}      Scales 200MHz - 1.2GHz (Experimental)"
    echo ""
    idx=0; if [ "$ENABLE_CPR" = true ]; then idx=1; fi
    menu_select "$idx" "No (Recommended - Fixed 998MHz)" "Yes (Experimental - 200MHz-1.2GHz)"
    if [[ "$SELECTED_INDEX" -eq 1 ]]; then ENABLE_CPR=true; else ENABLE_CPR=false; fi
    if [ "$ENABLE_CPR" = true ]; then log_warn "CPR Enabled"; else log_succ "CPR Disabled"; fi
    echo ""

    # Step 3: User Patches
    echo -e "${CYAN}${BOLD}Step 3: Extra User Patches${RESET}"
    shopt -s nullglob
    all_patches=("$PATCHES_DIR"/*.patch)
    shopt -u nullglob
    available_patches=()
    for p in "${all_patches[@]}"; do
        pname=$(basename "$p")
        [[ "$pname" != "$CPR_PATCH_NAME" ]] && available_patches+=("$pname")
    done

    if [ ${#available_patches[@]} -eq 0 ]; then
        echo -e "${DIM}No extra patches found in patches/${RESET}"
        CHOSEN_USER_PATCHES=()
    else
        menu_multiselect "Select additional patches to apply:" "${available_patches[@]}"
        CHOSEN_USER_PATCHES=("${SELECTED_PATCHES[@]}")
        if [ ${#CHOSEN_USER_PATCHES[@]} -gt 0 ]; then log_info "Selected: ${CHOSEN_USER_PATCHES[*]}"; else log_info "None selected."; fi
    fi
    echo ""

    # Step 4: Caching options
    echo -e "${CYAN}${BOLD}Step 4: Caching preference${RESET}"
    idx=1; [ "$FORCE_CLEAN" = true ] && idx=0
    menu_select "$idx" "Clean Build (Wipe cache, slower)" "Incremental Build (Keep cache, faster)"
    if [[ "$SELECTED_INDEX" -eq 0 ]]; then FORCE_CLEAN=true; else FORCE_CLEAN=false; fi
    log_succ "Caching preference set."
    echo ""

    # Step 5: Save
    echo -e "${CYAN}${BOLD}Step 5: Save Config${RESET}"
    menu_select "0" "Yes (Save defaults)" "No (One time run)"
    if [[ "$SELECTED_INDEX" -eq 0 ]]; then SAVE_CONFIG=true; else SAVE_CONFIG=false; fi
    if [ "$SAVE_CONFIG" = true ]; then
        echo -e "${YELLOW}Tip:${RESET} Next time, run with ${BOLD}--auto${RESET} to skip these questions and use your saved config."
    fi
fi

if [ "$SAVE_CONFIG" = true ]; then
    echo "KERNEL_VERSION=\"$KERNEL_VERSION\"" > "$CONFIG_FILE"
    echo "ENABLE_CPR=$ENABLE_CPR" >> "$CONFIG_FILE"
fi


# BUILD EXECUTION

# Start Timer
SECONDS=0

# Setup Tools and environment
log_info "Setting up tools..."
export PMBOOTSTRAP_WORKDIR="$PMOS_WORKDIR"

if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install --upgrade pip
else
    source "$VENV_DIR/bin/activate"
fi

# Fix for python older than 3.11
if ! python3 -c "import sys; exit(0) if sys.version_info >= (3, 11) else exit(1)"; then
    pip install tomli
fi

if [ ! -d "$PMBOOTSTRAP_DIR" ]; then
    git clone "https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git" "$PMBOOTSTRAP_DIR"
fi
pip install "$PMBOOTSTRAP_DIR"/ >/dev/null

mkdir -p "$PATCHES_DIR" "$PMOS_WORKDIR" "$BUILDS_DIR"
PMAPORTS_PATH="$PMOS_WORKDIR/cache_git/pmaports"
if [ ! -d "$PMAPORTS_PATH" ]; then
    mkdir -p "$PMOS_WORKDIR/cache_git"
    git clone --depth=1 "$PMAPORTS_GIT" "$PMAPORTS_PATH"
fi

log_info "Initializing pmbootstrap..."
yes "" | pmbootstrap -w "$PMOS_WORKDIR" -p "$PMAPORTS_PATH" init --shallow-initial-clone >/dev/null 2>&1 || true

# Configure pmbootstrap with the correct device as else it defaults to x86_64
pmbootstrap -w "$PMOS_WORKDIR" config device qcom-msm8916
pmbootstrap -w "$PMOS_WORKDIR" config ui console

if [ -d "$PMOS_WORKDIR/packages" ]; then sudo rm -rf "$PMOS_WORKDIR/packages"; fi

# Prepare kernel source
if [ ! -d "$KERNEL_SRC_DIR" ]; then
    log_info "Cloning $KERNEL_VERSION..."
    git clone --depth=1 --branch "$KERNEL_VERSION" "$REPO_URL" "$KERNEL_SRC_DIR"
else
    cd "$KERNEL_SRC_DIR"
    if ! git show-ref --verify --quiet "refs/remotes/origin/$KERNEL_VERSION"; then
            git fetch --depth=1 origin "$KERNEL_VERSION" 2>/dev/null || true
    fi
    git checkout "$KERNEL_VERSION" 2>/dev/null || (git fetch origin "$KERNEL_VERSION" --depth=1 && git checkout "$KERNEL_VERSION")
fi
cd "$KERNEL_SRC_DIR"
curl -sSL "$DEFCONFIG_URL" -o "$SCRIPT_DIR/downloaded_defconfig_temp"
#curl -sSL "$PMOS_CONFIG_URL" -o "$SCRIPT_DIR/pmos.config" # seems to break things but worked in initial testing will compile without it

# Activate environment
cd "$KERNEL_SRC_DIR"
ENVKERNEL="$PMBOOTSTRAP_DIR/helpers/envkernel.sh"
if [ ! -f "$ENVKERNEL" ]; then log_err "envkernel.sh not found!"; fi
log_info "Sourcing envkernel..."
source "$ENVKERNEL" --gcc

# Apply patches
cd "$KERNEL_SRC_DIR"
git checkout . >/dev/null 2>&1
git clean -fd >/dev/null 2>&1

# CPR Patch
CPR_FILE="$PATCHES_DIR/$CPR_PATCH_NAME"
if [ "$ENABLE_CPR" = true ]; then
    if [ -f "$CPR_FILE" ]; then
        log_info "Applying CPR Patch ($CPR_PATCH_NAME)..."
        if git apply "$CPR_FILE"; then
            log_succ "CPR patch applied."
        else
            log_warn "CPR patch failed (conflict?)"
        fi
    else
        log_warn "CPR enabled but patch not found."
    fi
else
    # CPR not selected: ensure any previously-applied CPR patch is reverted
    if [ -f "$CPR_FILE" ]; then
        log_info "CPR not selected: ensuring CPR patch is not applied..."
        # Try reversing the patch; git apply -R succeeds if the patch was applied
        if git apply -R "$CPR_FILE" >/dev/null 2>&1; then
            log_succ "CPR patch reverted."
        else
            log_warn "Could not reverse CPR patch automatically; attempting to reset affected files."
            files=$(git apply --numstat "$CPR_FILE" 2>/dev/null | awk '{print $3}')
            if [ -n "$files" ]; then
                if git checkout -- $files >/dev/null 2>&1; then
                    log_succ "Reset affected files: $files"
                else
                    log_warn "Failed to reset some files: $files"
                fi
            else
                # As a last resort, reset the working tree
                log_warn "No file list available from patch; performing a full checkout to ensure clean state."
                git checkout -- . >/dev/null 2>&1 || true
            fi
        fi
    fi
fi

# User Patches
if [ ${#CHOSEN_USER_PATCHES[@]} -gt 0 ]; then
    for patch_name in "${CHOSEN_USER_PATCHES[@]}"; do
        patch_path="$PATCHES_DIR/$patch_name"
        if [ -f "$patch_path" ]; then
            log_info "Applying: $patch_name"
            git apply "$patch_path" || log_warn "Failed to apply $patch_name"
        fi
    done
fi

# Build kernel
cd "$KERNEL_SRC_DIR"
OUT_DIR="$KERNEL_SRC_DIR/.output"
mkdir -p "$OUT_DIR"

# Permissions
chmod -R 777 "$OUT_DIR" 2>/dev/null || sudo chmod -R 777 "$OUT_DIR"
if command -v chcon &> /dev/null; then sudo chcon -Rt svirt_sandbox_file_t "$OUT_DIR" 2>/dev/null || true; fi

if [ "$FORCE_CLEAN" = true ]; then
    rm -rf "$OUT_DIR"/*
    rm -f "$KERNEL_SRC_DIR/.config"
fi

TARGET_CONFIG="$OUT_DIR/.config"
DEFCONFIG_NAME="postmarketos_qcom_msm8916_defconfig"

mkdir -p arch/arm64/configs
mv -f "$SCRIPT_DIR/downloaded_defconfig_temp" "arch/arm64/configs/$DEFCONFIG_NAME"
rm -f "$DEFCONFIG_NAME" .config

if [ -f "$TARGET_CONFIG" ] && [ "$FORCE_CLEAN" = false ]; then
    log_info "Using cached configuration."
else
    log_info "Generating configuration..."
    make "$DEFCONFIG_NAME"

    if [ -f "$SCRIPT_DIR/pmos.config" ]; then
        log_info "Merging pmos.config..."
        sudo chmod 666 "$TARGET_CONFIG" 2>/dev/null || true
        ./scripts/kconfig/merge_config.sh -n -m "$TARGET_CONFIG" "$SCRIPT_DIR/pmos.config"
        make olddefconfig
    fi

    # Kernel version configuration
    TAG="-msm8916"
    [ "$ENABLE_CPR" = true ] && TAG="-msm8916-cpr"
    
    log_info "Setting kernel localversion to '$TAG'..."
    sudo chmod 666 "$TARGET_CONFIG"
    if grep -q "CONFIG_LOCALVERSION=" "$TARGET_CONFIG"; then
        sed -i "s/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"$TAG\"/" "$TARGET_CONFIG"
    else
        echo "CONFIG_LOCALVERSION=\"$TAG\"" >> "$TARGET_CONFIG"
    fi
    make olddefconfig
fi

log_info "Compiling (Jobs: $(nproc))..."
make -j$(nproc) Image.gz dtbs modules

# Gzip check because some builds may not produce it directly
IMG_PATH="$OUT_DIR/arch/arm64/boot/Image"
IMG_GZ_PATH="$OUT_DIR/arch/arm64/boot/Image.gz"
if [ ! -f "$IMG_GZ_PATH" ] && [ -f "$IMG_PATH" ]; then
    gzip -fk "$IMG_PATH"
fi
if [ ! -f "$IMG_GZ_PATH" ]; then log_err "Image.gz missing."; fi

# Fetch apkbuild and prepare kernel to be packaged
cd "$PMOS_WORKDIR/cache_git/pmaports"
git checkout device/testing/linux-postmarketos-qcom-msm8916/APKBUILD 2>/dev/null || true
APKBUILD="device/testing/linux-postmarketos-qcom-msm8916/APKBUILD"

# Update pkgrel
sed -i 's/^pkgrel=.*/pkgrel=99/' "$APKBUILD"

log_info "Updating checksums..."
cd "$SCRIPT_DIR"
pmbootstrap -w "$PMOS_WORKDIR" -p "$PMAPORTS_PATH" checksum linux-postmarketos-qcom-msm8916

log_info "Packaging..."
pmbootstrap -w "$PMOS_WORKDIR" -p "$PMAPORTS_PATH" -y build --envkernel linux-postmarketos-qcom-msm8916

deactivate

# Finalize and cleanup
log_info "Shutting down pmbootstrap..."
pmbootstrap -w "$PMOS_WORKDIR" shutdown

log_info "Moving artifacts to builds/ folder..."

# Find the generated APK
GENERATED_APK=$(find "$PMOS_WORKDIR/packages/edge/aarch64" -name "linux-postmarketos-qcom-msm8916-*.apk" -type f | head -n 1)

if [ -f "$GENERATED_APK" ]; then
    BASE_NAME="linux-postmarketos-qcom-msm8916"
    EXTRA=""
    [ "$ENABLE_CPR" = true ] && EXTRA="-cpr"
    
    # Clean version string for filename
    FINAL_VER=$(echo "$KERNEL_VERSION" | sed 's|.*/||; s|^v||')
    
    TARGET_NAME="${BASE_NAME}${EXTRA}-${FINAL_VER}.apk"
    
    cp "$GENERATED_APK" "$BUILDS_DIR/$TARGET_NAME"
    
    DURATION=$SECONDS
    TIME_STR="$(($DURATION / 60))m $(($DURATION % 60))s"

    echo ""
    echo "#######################################################"
    echo "SUCCESS!"
    echo "Build Saved to: $BUILDS_DIR/$TARGET_NAME"
    echo "Time Elapsed:   $TIME_STR"
    echo "#######################################################"
else
    log_err "Could not find generated APK in workdir."
fi