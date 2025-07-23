#!/bin/sh

# Enhanced 3proxy installer with proper reinstallation handling

# Function to generate random strings
random() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Array for IPv6 generation
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Function to generate IPv6 addresses
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Fixed 3proxy installer with correct binary path handling

# Function to locate the compiled binary
find_3proxy_binary() {
    # Check possible locations
    [ -f "src/3proxy" ] && echo "src/3proxy" && return
    [ -f "bin/3proxy" ] && echo "bin/3proxy" && return
    [ -f "3proxy" ] && echo "3proxy" && return
    echo ""
}

install_3proxy() {
    echo -e "\n[2/6] COMPILING AND INSTALLING 3PROXY..."
    
    rm -rf 3proxy
    git clone https://github.com/z3APA3A/3proxy.git || {
        echo "ERROR: Failed to clone repository"
        exit 1
    }
    
    cd 3proxy
    echo '#define ANONYMOUS 1' >> ./src/proxy.h
    
    # Compile with verbose output
    echo "Compiling 3proxy (this may take a few minutes)..."
    make -f Makefile.Linux | tee -a /tmp/proxy_install.log || {
        echo "ERROR: Compilation failed"
        exit 1
    }
    
    # Find the compiled binary
    BINARY_PATH=$(find_3proxy_binary)
    if [ -z "$BINARY_PATH" ]; then
        echo "ERROR: Could not find compiled 3proxy binary"
        echo "Searched in:"
        find . -name "3proxy" | tee -a /tmp/proxy_install.log
        exit 1
    fi
    
    echo "Found binary at: $BINARY_PATH"
    
    # Install to system location
    mkdir -p /usr/local/etc/3proxy/bin
    cp "$BINARY_PATH" /usr/local/etc/3proxy/bin/ || {
        echo "ERROR: Failed to copy binary"
        exit 1
    }
    
    # Create init script
    cat > /etc/init.d/3proxy <<'EOL'
#!/bin/sh
case "$1" in
    start)
        /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
        ;;
    stop)
        pkill -9 3proxy
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
esac
exit 0
EOL
    
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd ..
    echo "✓ 3Proxy installed successfully"
}

# [Rest of your existing functions remain the same...]

### Main Script Execution ###

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Initialize working directory
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

# Check for previous installation
if [ -f "$WORKDATA" ]; then
    echo "Warning: Found existing proxy data at $WORKDATA"
    echo "This suggests the script was run before."
    echo "Do you want to perform a fresh installation? (This will remove all existing proxies) [y/N]"
    read FRESH_INSTALL
    if [ "$FRESH_INSTALL" != "y" ] && [ "$FRESH_INSTALL" != "Y" ]; then
        echo "Aborting..."
        exit 0
    fi
    echo "Cleaning up previous installation..."
    rm -rf "$WORKDIR"
    mkdir -p $WORKDIR && cd $WORKDIR
fi

echo "Starting proxy installation..."
echo "Setting up working directory in $WORKDIR"

# Get IP addresses
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IPv4 = ${IP4}"
echo "External IPv6 prefix = ${IP6}"

# Get proxy count
echo "How many proxies do you want to create? (e.g., 500)"
read COUNT
FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

# Install 3proxy first to ensure binary exists
install_3proxy

# Generate data
echo "Generating proxy data..."
gen_data >$WORKDATA

# Generate config files
echo "Generating configuration files..."
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh

# Generate 3proxy config
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Set up rc.local
echo "Setting up startup configuration..."
cat >/etc/rc.local <<'EOL'
#!/bin/bash
# 3proxy startup script

# Wait for network
sleep 10

# Load iptables rules
[ -f /home/proxy-installer/boot_iptables.sh ] && bash /home/proxy-installer/boot_iptables.sh

# Configure IPv6 addresses
[ -f /home/proxy-installer/boot_ifconfig.sh ] && bash /home/proxy-installer/boot_ifconfig.sh

# Increase file descriptor limit
ulimit -n 10048

# Start 3proxy
[ -f /usr/local/etc/3proxy/bin/3proxy ] && /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

exit 0
EOL
chmod +x /etc/rc.local

# Start services
echo "Starting services..."
systemctl daemon-reload
/etc/rc.local

# Generate proxy list files
echo "Generating proxy list files..."
gen_proxy_file_for_user
gen_proxy_file_for_user2

echo "Installation complete!"
echo "Proxy list generated in $WORKDIR/proxy.txt"
echo "You can find both IP:PORT:LOGIN:PASS and socks5:// formats"
echo "To start/stop 3proxy: service 3proxy {start|stop|restart}"
