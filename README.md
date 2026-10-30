# purpose

This repository contains the code designed to be used in operations on
the various pieces of the R2lab testbed, typically

* users and root environment on the gateway and infrastructure
* user environment on nodes
* user environment on (mac)phones
* node-side helpers for building images (the build tooling itself is in `r2lab-imaging`)

It is designed to be small, and the corresponding public git repo acts
like a software distribution hub. In this respect, it comes with
shortcuts (shell functions) that can be used to update itself.

# related repos

* https://github.com/fit-r2lab/rhubarbe
  the command-line tools (and library) to drive the testbed nodes
* https://github.com/fit-r2lab/r2lab-api
  the API server
* https://github.com/fit-r2lab/r2lab.inria.fr
  the sources of the r2lab website
* https://github.com/fit-r2lab/r2lab.inria.fr-raw
  large static assets for the web site
* https://github.com/fit-r2lab/r2lab-sidecar
  the sidecar server, that relays live testbed status to the website
* https://github.com/fit-r2lab/r2lab-nightly
  the nightly health check of the testbed, and its distrait counterpart
  turn-off-the-lights; these used to live here in `nightly/`
* https://github.com/fit-r2lab/r2lab-imaging
  the tooling and notes for building the testbed's images, both frisbee
  and docker; these used to live here in `imaging/` and `docker-images/`
* https://github.com/fit-r2lab/r2lab-misc
  miscellaneous material

# related hosts

- `r2lab.inria.fr` runs the website, and the sidecar
- `r2labapi.inria.fr` runs the API and DB
- `faraday.inria.fr` is the testbed main gateway, it has physical connectivity to the nodes
- finally `distrait.pl.sophia.inria.fr` is the gateway for the preplab (aka "V0"), in a
  regular office where nodes can be repaired and tweaked

as well as, of course, the testbed nodes themselves that also may pull the
current repo in order to stay current in terms of helper tools

# auto-updates

the entry point to the testbed auto-updating code is here in  
`./services/run-updates.sh`  
which is configured by dropins under  
`./services/hosts`

each dropin lists, for a specific host, the repos that need to be pulled, and
each repo comes with its own `deploy/update.sh` which gets run whenever a change
occurs in said repo

# history

This contents used to be (a long time ago) part of a wider repo at
https://github.com/parmentelat/r2lab/infra **old location**

But that one became way too large over time, and it appeared soon
that a split was required, if only so that updates could run more
efficiently

It won't be possible to update all the r2lab images to reflect
this change, at least not overnight.

For that reason, the big `r2lab` repo is still available but was
archived under github.
