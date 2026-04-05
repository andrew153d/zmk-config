#!/bin/bash
set -e

# Get the absolute path to the zmk-config directory (this script's parent directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZMK_CONFIG_PATH="$SCRIPT_DIR"

# Container and image settings
CONTAINER_NAME="zmk-dev"
IMAGE_NAME="zmk-build-env"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ZMK Firmware Build Script ===${NC}"

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    echo -e "${YELLOW}Error: podman is not installed. Please install podman first.${NC}"
    exit 1
fi

# Clone ZMK if it doesn't exist
if [ ! -d "$SCRIPT_DIR/zmk" ]; then
    echo -e "${GREEN}Cloning ZMK repository...${NC}"
    git clone https://github.com/zmkfirmware/zmk.git "$SCRIPT_DIR/zmk"
    cd "$SCRIPT_DIR/zmk"
    git checkout main
    cd "$SCRIPT_DIR"
else
    echo -e "${GREEN}ZMK repository already exists${NC}"
fi

# Build the container image if it doesn't exist
if ! podman image exists "$IMAGE_NAME"; then
    echo -e "${GREEN}Building container image...${NC}"
    podman build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/zmk/.devcontainer/Dockerfile" "$SCRIPT_DIR/zmk/.devcontainer/"
else
    echo -e "${GREEN}Container image already exists${NC}"
fi

# Run the container and execute build commands
echo -e "${GREEN}Starting container and building firmware...${NC}"
podman run -it --rm \
    --name "$CONTAINER_NAME" \
    --security-opt label=disable \
    --workdir /workspaces/zmk \
    -v "$SCRIPT_DIR/zmk:/workspaces/zmk" \
    -v "$ZMK_CONFIG_PATH:/workspaces/zmk-config" \
    "$IMAGE_NAME" /bin/bash -c "
        set -e
        echo -e '${BLUE}=== Initializing West Workspace ===${NC}'
        
        # Initialize west workspace if not already done
        if [ ! -f .west/config ]; then
            west init -l app/
            west update
        else
            echo 'West workspace already initialized'
            west update
        fi
        
        echo -e '${BLUE}=== Building Firmware ===${NC}'
        
        # Build for corne_left
        echo -e '${GREEN}Building corne_left...${NC}'
        west build -s app -b nice_nano -d build/left -- -DZMK_CONFIG=/workspaces/zmk-config/config -DSHIELD=corne_left
        
        # Build for corne_right
        echo -e '${GREEN}Building corne_right...${NC}'
        west build -s app -b nice_nano -d build/right -- -DZMK_CONFIG=/workspaces/zmk-config/config -DSHIELD=corne_right
        
        echo -e '${BLUE}=== Copying firmware files ===${NC}'
        mkdir -p /workspaces/zmk-config/firmware
        cp build/left/zephyr/zmk.uf2 /workspaces/zmk-config/firmware/corne_left-nice_nano-zmk.uf2
        cp build/right/zephyr/zmk.uf2 /workspaces/zmk-config/firmware/corne_right-nice_nano-zmk.uf2
        
        echo -e '${GREEN}=== Build Complete! ===${NC}'
        echo -e 'Firmware files saved to: firmware/'
        ls -lh /workspaces/zmk-config/firmware/
    "

echo -e "${GREEN}=== Done! ===${NC}"
echo -e "Firmware files are in: ${BLUE}$SCRIPT_DIR/firmware/${NC}"