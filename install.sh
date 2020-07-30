
enable_bbr()
{
    enable_bbr_force()
    {
        echo "BBR not enabled. Enabling BBR..."
        echo 'net.core.default_qdisc=fq' | tee -a /etc/sysctl.conf
        echo 'net.ipv4.tcp_congestion_control=bbr' | tee -a /etc/sysctl.conf
        sysctl -p
    }
    sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr ||  enable_bbr_force
}

get_port()
{
    while true; 
    do
        local PORT=$(shuf -i 40000-65000 -n 1)
        ss -lpn | grep -q ":$PORT " || echo $PORT && break
    done
}

open_port()
{
    port_to_open="$1"
    if [[ "$port_to_open" == "" ]]; then
        echo "You must specify a port!'"
        return 9
    fi

    ufw allow $port_to_open/tcp
    ufw reload
}

enable_firewall()
{
    open_port 22
    echo "y" | ufw enable
}

add_caddy_proxy()
{
    domain_name="$1"
    local_port="$2"
    cat /etc/caddy/Caddyfile | grep -q "an easy way" && echo "" > /etc/caddy/Caddyfile
    echo "
$domain_name {
    reverse_proxy /* 127.0.0.1:$local_port
}" >> /etc/caddy/Caddyfile
    systemctl restart caddy.service
}

register_service()
{
    service_name="$1"
    local_port="$2"
    run_path="$3"
    dll="$4"
    echo "[Unit]
    Description=$dll Service
    After=network.target
    Wants=network.target

    [Service]
    Type=simple
    ExecStart=/usr/bin/dotnet $run_path/$dll.dll --urls=http://localhost:$local_port/
    WorkingDirectory=$run_path
    Restart=on-failure
    RestartPreventExitStatus=10

    [Install]
    WantedBy=multi-user.target" > /etc/systemd/system/$service_name.service
    systemctl enable $service_name.service
    systemctl start $service_name.service
}

add_source()
{
    wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -r -s)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb && rm ./packages-microsoft-prod.deb
    cat /etc/apt/sources.list.d/caddy-fury.list | grep -q caddy || echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" | tee -a /etc/apt/sources.list.d/caddy-fury.list
    apt update
}

install_tracer()
{
    server="$1"
    echo "Installing Tracer to domain $server..."

    # Valid domain is required
    ip=$(dig +short $server)
    if [[ "$server" == "" ]] || [[ "$ip" == "" ]]; then
        echo "You must specify your valid server domain. Try execute with 'bash -s www.a.com'"
        return 9
    fi

    if [[ $(ifconfig) == *"$ip"* ]]; 
    then
        echo "The ip result from domian $server is: $ip and it is your current machine IP!"
    else
        echo "The ip result from domian $server is: $ip and it seems not to be your current machine IP!"
        return 9
    fi

    port=$(get_port)
    echo "Using internal port: $port"

    cd ~

    # Enable BBR
    enable_bbr

    # Install basic packages
    echo "Installing packages..."
    add_source
    apt install -y apt-transport-https curl git vim dotnet-sdk-3.1 caddy

    # Download the source code
    echo 'Downloading the source code...'
    ls | grep -q Tracer && rm ./Tracer -rf
    git clone https://github.com/AiursoftWeb/Tracer.git

    # Build the code
    echo 'Building the source code...'
    tracer_path="$(pwd)/apps/TracerApp"
    dotnet publish -c Release -o $tracer_path ./Tracer/Tracer.csproj
    rm ~/Tracer -rvf

    # Register tracer service
    echo "Registering Tracer service..."
    register_service "tracer" $port $tracer_path "Tracer"

    # Config caddy
    echo 'Configuring the web proxy...'
    add_caddy_proxy $server $port

    # Config firewall
    enable_firewall
    open_port 443
    open_port 80

    # Finish the installation
    echo "Successfully installed Tracer as a service in your machine! Please open https://$server to try it now!"
    echo "Strongly suggest run 'sudo apt upgrade' on machine!"
    echo "Strongly suggest to reboot the machine!"
}

install_tracer "$@"
