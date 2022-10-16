#!/bin/bash
# how we started the service

# see also
# https://docs.docker.com/registry/deploying/

mkdir -p /var/lib/docker-registry

podman run -d -p 443:443 \
       --restart=always \
       -v /var/lib/docker-registry:/var/lib/registry \
       -v /root/docker-registry/certs:/certs \
       -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
       -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/sopnode-registry.crt \
       -e REGISTRY_HTTP_TLS_KEY=/certs/sopnode-registry.key \
       --name docker-registry registry:2
