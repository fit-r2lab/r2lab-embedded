SHELL=/bin/sh
HOME=/root
PATH=/root/bin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin
python3 /root/r2lab/infra/nightly/nightly.py >> /var/log/nightly.log 2>&1
