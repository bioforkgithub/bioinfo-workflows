#!/bin/bash
# Run every time the codespace starts again:  bash codespace/start_slurm.sh
# (Nothing starts by itself in a codespace.)

sudo service mariadb start > /dev/null                 # job database
sudo mkdir -p /run/munge && sudo chown munge:munge /run/munge
pgrep -x munged    >/dev/null || sudo runuser -u munge -- /usr/sbin/munged
pgrep -x slurmdbd  >/dev/null || sudo slurmdbd
sleep 3
# register the cluster in the database (only does something the first time)
sudo sacctmgr -i add cluster mini > /dev/null 2>&1 || true
pgrep -x slurmctld >/dev/null || sudo slurmctld
pgrep -x slurmd    >/dev/null || sudo slurmd
sleep 5
# if the node came up "down", set it back to work
sudo scontrol update nodename="$(hostname -s)" state=resume 2>/dev/null || true
sinfo
