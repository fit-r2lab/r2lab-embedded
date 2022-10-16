# docker registry setup

* runs on https://sopnode-registry.inria.fr:5000/
* using filesystem /var/lib/docker-registry
* current certificate and key stored in `./certs/`  
  see `fit-r2lab/misc/ssl-certificate-renewal/README.md`  
  on the procedure to renew these

## running the service

* see local `docker-registry.sh` for the options used to start the service
* and, as we use podman instead of docker, in order for it to survive reboots,
  it is required to do
  ```
  systemctl enable podman-restart
  ```
  that will take care of starting containers that are run with `--restart=always` like we do here
