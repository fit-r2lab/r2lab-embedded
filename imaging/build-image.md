# Purpose

`build-image.py` is a tool for automating the simple process of

* loading an image `from_image`
* run some scripts
* saving the image as `to_image`

The actual set of scripts and their logs are all preserved on the node in `/etc/rhubarbe-history`

# Warnings

* Tool is for local usage only

# Synopsis

```
build-image.py gateway node from_image to_image scripts...
```

# Examples

## Use `-f/--fast` to avoid actually loading/saving image

For debugging script `foo.sh`

```
build-image.py -f root@faraday.inria.fr fit02 ubuntu ubuntu-prime foo.sh
```

## Run a script with an argument
```
build-image.py root@faraday.inria.fr fit02 ubuntu ubuntu-prime "./imaging.sh init-node-ssh-key"
```

## Run a few scripts

Here 3 scripts:

```
build-image.py root@faraday.inria.fr fit02 ubuntu ubuntu-prime foo.sh bar.sh "./imaging.sh init-node-ssh-key"
```

## Included bash

In particular for the stuff in `r2lab/infra/user-env`; for example

`oai-gw.sh` requires `nodes.sh` and `oai-common.sh`

```
~/git/r2lab/infra/user-env $ ../../rhubarbe-images/build-image.py -f $(plr faraday) 1 ubuntu-16.04-v4-node-env oai1609-gw-001 "oai-gw.sh cn-git-fetch" -i oai-common.sh -i nodes.sh
```


## Inspect results

On target node:

```
# cd /etc/rhubarbe-history/ubuntu-prime
# ls
args  logs  scripts
# ls -ls scripts
total 8
8 -rwx------. 1 502 games 5142 Sep 28  2016 001-imaging.sh
# ls -l logs
total 4
-rw-r--r--. 1 root root 178 Sep 28 00:02 001-imaging.sh.log
```
