#!/bin/sh

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

# Function to install 3proxy from source
install_3proxy() {
    echo "Checking for existing 3proxy installation..."
    
    # Check if 3proxy is already installed and running
    if [ -f /usr/local/etc/3proxy/bin/3proxy ]; then
        echo "3proxy is already installed at /usr/local/etc/3proxy/bin/3proxy"
        echo "Do you want to reinstall? [y/N]"
        read REINSTALL
        if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
            return 0
        fi
        echo "Removing previous installation..."
        rm -rf /usr/local/etc/3proxy
        pkill 3proxy
    fi

    echo "Installing dependencies..."
    yum -y install gcc make git libbsd bsdtar zip >/dev/null

    echo "Preparing 3proxy source..."
    if [ -d "3proxy" ]; then
        echo "Found existing 3proxy directory, cleaning up..."
        rm -rf 3proxy
    fi

    echo "Cloning fresh 3proxy source..."
    git clone https://github.com/z3APA3A/3proxy || {
        echo "Failed to clone 3proxy repository!"
        exit 1
    }

    cd 3proxy
    
    # Apply anonymous patch
    echo '#define ANONYMOUS 1' >> ./src/proxy.h
    
    echo "Compiling 3proxy..."
    make -f Makefile.Linux || {
        echo "3proxy compilation failed!"
        exit 1
    }
    
    echo "Installing 3proxy..."
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/ || {
        echo "Failed to copy 3proxy binary!"
        exit 1
    }
    
    if [ -f "./scripts/rc.d/proxy.sh" ]; then
        cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
        chmod +x /etc/init.d/3proxy
        chkconfig 3proxy on
    else
        echo "Warning: Could not find init script at ./scripts/rc.d/proxy.sh"
        echo "You may need to set up service management manually"
    fi
    
    cd ..
    echo "3proxy installed successfully"
}

# Function to generate 3proxy config
gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"socks -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate proxy list files
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

gen_proxy_file_for_user2() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print "socks5://" $1 ":" $2 "@" $3 ":" $4}' ${WORKDATA})
EOF
}

# Function to upload proxy list
upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

# Function to generate proxy data
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables rules
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

# Function to generate ifconfig commands
gen_ifconfig() {
    # Detect main network interface
    INTERFACE=$(ip route | awk '/default/ {print $5}')
    cat <<EOF
$(awk -F "/" '{print "ifconfig $INTERFACE inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

### Main Script Execution ###

echo "Starting proxy installation..."

# Create working directory
echo "Setting up working directory..."
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

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

# Generate data
echo "Generating proxy data..."
gen_data >$WORKDATA

# Generate config files
echo "Generating configuration files..."
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh

# Install 3proxy
install_3proxy

# Generate 3proxy config
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

# Set up rc.local
echo "Setting up startup configuration..."
cat >>/etc/rc.local <<EOF
#!/bin/bash
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
service 3proxy start
exit 0
EOF
chmod +x /etc/rc.local

# Start services
echo "Starting services..."
bash /etc/rc.local

# Generate proxy list files
echo "Generating proxy list files..."
gen_proxy_file_for_user
gen_proxy_file_for_user2

# Upload proxy list (optional)
# upload_proxy

echo "Installation complete!"
echo "Proxy list generated in $WORKDIR/proxy.txt"
echo "You can find both IP:PORT:LOGIN:PASS and socks5:// formats"
