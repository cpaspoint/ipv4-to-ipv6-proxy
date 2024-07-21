#!/bin/bash

# Function to generate a random alphanumeric string of length 5
generate_random_string() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Array of hexadecimal characters
hex_chars=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Function to generate a random 64-bit IP segment
generate_64bit_ip_segment() {
  local segment
  for _ in {1..4}; do
    segment+="${hex_chars[RANDOM % 16]}"
  done
  echo "$segment"
}

# Function to generate a 64-bit IP address using the provided prefix
generate_64bit_ip_address() {
  local prefix=$1
  echo "$prefix:$(generate_64bit_ip_segment):$(generate_64bit_ip_segment):$(generate_64bit_ip_segment):$(generate_64bit_ip_segment)"
}

# Function to install and configure 3proxy
install_and_configure_3proxy() {
  echo "Installing 3proxy..."
  git clone https://github.com/z3APA3A/3proxy
  cd 3proxy/
  echo '#define ANONYMOUS 1' >> ./src/proxy.h
  ln -s Makefile.Linux Makefile
  make
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp bin/3proxy /usr/local/etc/3proxy/bin/
  cd "$WORKDIR"
}

# Function to generate the 3proxy configuration file
create_3proxy_config() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN {ORS="";} {print $1 ":CL:" $2 " "}' "$WORKDATA")

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\n" \
"flush\n"}' "$WORKDATA")
EOF
}

# Function to generate a proxy file listing for users
generate_proxy_list() {
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "$WORKDATA" > proxy.txt
}

# Function to generate proxy data entries
create_proxy_data() {
    seq "$FIRST_PORT" "$LAST_PORT" | while read -r port; do
        echo "usr$(generate_random_string)/pass$(generate_random_string)/$IP4/$port/$(generate_64bit_ip_address $IP6)"
    done
}

# Function to generate iptables rules based on the proxy data
create_iptables_rules() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' "$WORKDATA"
}

# Function to generate ifconfig commands based on the proxy data
create_ifconfig_commands() {
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev enp1s0"}' "$WORKDATA"
}

# Main script execution
main() {
  echo "Installing required applications..."
  dnf -y install gcc net-tools bsdtar zip iptables-services >/dev/null || { echo "Package installation failed"; exit 1; }

  echo "Setting up working directory..."
  WORKDIR="/home/proxy-installer"
  WORKDATA="${WORKDIR}/data.txt"
  mkdir -p "$WORKDIR" || { echo "Failed to create working directory"; exit 1; }

  IP4=$(curl -4 -s icanhazip.com)
  IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

  echo "Internal IP: ${IP4}. External IPv6 subnet: ${IP6}"

  echo "Enter the number of proxies to create (e.g., 500):"
  read -r COUNT

  FIRST_PORT=10000
  LAST_PORT=$((FIRST_PORT + COUNT - 1))

  create_proxy_data > "$WORKDATA"
  create_iptables_rules > "$WORKDIR/boot_iptables.sh"
  create_ifconfig_commands > "$WORKDIR/boot_ifconfig.sh"
  chmod +x "$WORKDIR/boot_*.sh"

  install_and_configure_3proxy
  create_3proxy_config > /usr/local/etc/3proxy/3proxy.cfg
    
  bash ${WORKDIR}/boot_iptables.sh
  bash ${WORKDIR}/boot_ifconfig.sh
  sudo systemctl stop firewalld
  sudo systemctl disable firewalld
  /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

  generate_proxy_list
  cat /home/proxy-installer/proxy.txt
}

main
