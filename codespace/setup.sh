#!/bin/bash
# Run ONCE in a new codespace:  bash codespace/setup.sh
# Installs Java 17+, Nextflow and a one-computer SLURM cluster
# (with a small job database, so sacct works).
set -euo pipefail

echo "== Java =="
if ! java -version 2>&1 | grep -qE 'version "(1[7-9]|[2-9][0-9])'; then
    sudo apt-get update
    sudo apt-get install -y openjdk-17-jre-headless
fi
java -version

echo "== Nextflow =="
if ! command -v nextflow >/dev/null; then
    curl -s https://get.nextflow.io | bash
    sudo mv nextflow /usr/local/bin/
fi
nextflow -version

echo "== SLURM + munge + job database =="
sudo apt-get update || true      # a broken extra repo must not stop us
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y slurm-wlm slurmdbd munge mariadb-server

CONF=/etc/slurm
H=$(hostname -s)
MEM=$(( $(free -m | awk '/Mem:/{print $2}') - 1000 ))   # leave 1 GB for the system
# the node line as slurmd sees the hardware (sockets/cores/threads), with our memory
NODE=$(slurmd -C | head -1 | sed "s/RealMemory=[0-9]*/RealMemory=$MEM/")

sudo mkdir -p /var/spool/slurmctld /var/spool/slurmd /var/log/slurm
sudo tee $CONF/slurm.conf > /dev/null <<CFG
ClusterName=mini
SlurmctldHost=$H
SlurmUser=root
AuthType=auth/munge
MpiDefault=none
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU_Memory
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=localhost
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherParams=OverMemoryKill
JobAcctGatherFrequency=5
JobCompType=jobcomp/filetxt
JobCompLoc=/var/log/slurm/jobcomp.log
MinJobAge=3600
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
ReturnToService=2
$NODE State=UNKNOWN
PartitionName=normal Nodes=$H Default=YES MaxTime=INFINITE State=UP
CFG

# a codespace has no systemd, so slurmd must not try to make cgroup scopes
echo "CgroupPlugin=cgroup/v1" | sudo tee $CONF/cgroup.conf > /dev/null

# job database: slurmdbd stores jobs in MariaDB
sudo tee $CONF/slurmdbd.conf > /dev/null <<CFG
AuthType=auth/munge
DbdHost=localhost
SlurmUser=root
StorageType=accounting_storage/mysql
StorageHost=localhost
StorageUser=slurm
StoragePass=slurmpass
StorageLoc=slurm_acct_db
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/run/slurmdbd.pid
CFG
sudo chmod 600 $CONF/slurmdbd.conf

# munge needs a key (sudo test: /etc/munge is readable only by the munge user)
if ! sudo test -f /etc/munge/munge.key; then
    sudo dd if=/dev/urandom of=/etc/munge/munge.key bs=1024 count=1 status=none
fi
sudo chown munge:munge /etc/munge/munge.key && sudo chmod 400 /etc/munge/munge.key

# stop old daemons, start everything with the new config
sudo pkill -x slurmd || true; sudo pkill -x slurmctld || true; sudo pkill -x slurmdbd || true; sleep 2
sudo service mariadb start
sudo mysql -e "CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'slurmpass';
               GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost'; FLUSH PRIVILEGES;"
bash "$(dirname "$0")/start_slurm.sh"
echo "== Done. You have $(nproc) CPUs and $MEM MB memory for jobs. =="
