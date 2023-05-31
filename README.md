## Stuff to know

`community.general` collection is required:

    ansible-galaxy collection install community.general

You should be able to SSH as root for user creation and setup playbook `create_user`

`create_user` playbook will setup user `user` with group `user` to `sudo` without password. Change it in `create_user.yaml.ansible` if you want to.

## Getting ready to run

Copy `vars.example.yaml` to `vars.yaml` or wherever and fill it in

Set your DigitalOcean DNS `A` records for `{{domain}}` and `*.{{domain}}` pointing to your server IP address.

Put your desired public SSH keys into `files/` with prefix `ssh_key_`, i.e.: `files/ssh_key_1`, `files/ssh_key_phone`, etc.

Put your `{{domain}}` into ansible inventory.

## How to run

Setup environment for convinience

    export NODE={{domain}}
    export VARS=vars.yaml

First run create user playbook

    ansible-playbook -u root -l $NODE -K --extra-vars '@'$VARS create_user.yaml.ansible

Then run the rest

    ansible-playbook -u user -l $NODE -K --extra-vars '@'$VARS all.yaml.ansible


After running this one you'll need to log in to grafana web UI (at `https://stats.{{domain}}`), set up prometheus data source, import grafana dashboard json from `files/prometheus/grafana-dashboard.json` and maybe set it as default.

Do not forget to update software:

    ssh user@{{domain}}
    sudo apt update
    sudo apt upgrade
    sudo systemctl reboot

## Result

There should be pihole admin panel available at `https://ph.{{domain}}/admin`

There should be grafana available at `https://stats.{{domain}}`

There should be `wg.pl` script, run it to add/remove/list your VPN users.

    sudo wg.pl # display help
    sudo wg.pl add <name> # config will reside at /etc/wireguard/clients/<username>.conf
    sudo wg.pl list
    sudo wg.pl remove <name>

<!-- TODO prometheus and grafana for fail2ban -->
<!-- TODO notification on ssh connect -->
