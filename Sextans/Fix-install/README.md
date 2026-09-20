# Sextans Fix Installation

Sextans Fix is the FAIR data record component of the Sextans Suite.  It can be run independently of Sextans Sight, and is intended to be deployed on a separate network segment with appropriate security for handling (anonymized) clinical records.

It consists of 4 "dockreized" components, all of them _mandatory_, but with different requirements for activation.

- Virtuoso - holds the RDF-formatted record data
- Transformation Daemon - this is the orchestrator for the RDF transformation
- Yarrrml-rdfizer - this executes the CSV to RDF transformation using the CARE-SM models
- CARE-SM - this does enrichment and quality control over the CSV data prior to transformation



## CONTENTS

- [Installation requirements](#requirements)
- [Downloading Fix](#downloading)
- [Installing Sight](#installing)
- [Quick Start - Data Transformations](#testing)

<a name="requirements"></a>

## Requirements

To use Sextans Fix you `must` meet the following requirements.

**User requirements (Person who is deploying this solution)**

- Basic knowledge about Docker​
- Basic GitHub knowledge​

**System requirements​ (Machine where this solution is being deployed)**

- Docker engine ​
- Docker-compose application​

---

<a name="downloading"></a>

## Downloading

#### Sextans Fix

To get Sextans Fix clone this repository to your machine.

```sh
git clone https://github.com/wilkinsonlab/Sextans-Suite.git
```

---



## Installing

<a name="installing"></a>

## Preparing for Installation

At the beginning of the installation process you are asked four questions:

### A Prefix for your installation
The prefix is used as a "namespace" to isolate indepdent Fix installations from one another.  This allows you to run multiple CARE-SM Data servers on the same machine.  The prefix is used for the docker network, docker volumes, and appears in the configuration files and docker-compose yaml files.  This can be any set of letter/number characters.  Please do not use punctuation characters.  e.g. 'euronmd1'  We will use *'ACME'* for the remainder of this document.

### Port for your Virtuoso database
This is the port that will be used by the Virtuoso database.  This is validated against a list of "banned" ports (ports that are likely to be used by other software on your system).  It is a good idea to stay in the range of ~4000-10000.  By detault, this port is disabled after installation, so your Virtuoso instance cannot be accessed.  This port does NOT need to be enabled for the regular operation of Sight, and should be disabled when not needed.

### Port for the transformation daemon
This is the port that will listen for requests to trigger a data transformation. It responds only to an "empty" HTTP GET request, does not allow any parameters, and does not process the HTTP request in any way.

### Virtuoso dba password
Virtuoso ships with no password set for its `dba` superuser until one is configured. The
installer asks you to choose a password (minimum 12 characters) and configures Virtuoso with it
automatically during installation, via the container's own `DBA_PASSWORD` startup setting. Keep
this password somewhere safe; it is also written (file mode 600) into the generated `.env` file
in your production server folder.


## Installing Sextans Fix

Once you have completed the "Downloading" section of this tutorial, and you have prepared your answers to the questions, cd into the `/Fix-install/` folder and run the instaler.

```
bash ./install-sextans-fix.sh
```

This script will bootstrap Virtuoso, secured with the password you chose. Virtuoso is a single database per instance (unlike GraphDB, it has no separate "repositories" to create) -- isolation between different prefix installs sharing a host comes from each install running its own Virtuoso container and volume, not from graph naming. Your record data is written into the named graphs specified by the CARE-SM transformation output itself (one graph per patient record, e.g. *http://my.domain.org/data/&lt;id&gt;_Record*), not into a single graph named after your prefix.

### If you abort installation before it completes...

This can (and probably will) leave you in a state that needs some careful attention.  In particular, find any Virtuoso Docker Volumes *_that have your PREFIX_* and remove them `docker volume rm ACME-virtuoso`.  If it will not delete, it will be due to the existence of a docker container that uses it.  You can safely delete this docker container also.  `docker rm AJDIRDjdsfhwe83hewfewkw5`.  Again, make sure you are deleting the right things!


### The folder with your final server configuration

The installer will create a sub-folder `ACME-Sextans-Fix` underneath the folder where you ran your installation. This folder contains all of your server configuration files.  You can copy this folder anywhere on your system, e.g. to keep your servers all in one folder outside of your GitHub copy.  Inside that folder is a customized docker-compose file (docker-compose-ACME.yml) for your deployment.  So for example, you would issue the commands:

```

cp -r ACME-Sextans-Fix ~/SERVERS/
cd ~/SERVERS/ACME-Sextans-Fix
docker-compose -f docker-compose-ACME.yml up

```

Your Fix server is now running at whatever port you selected.

## Securing your Sextans Fix server

In principle, none of these components will have any internet-facing interfaces; nevertheless
Virtuoso is secured as part of installation.

These are the default login details and locations:

#### Virtuoso

| Service name | Local deployment                                | Production deployment |
| ------------ | ----------------------------------------------- | --------------------- |
| Virtuoso     | [http://localhost:8890](http://localhost:8890/) | SHOULD NOT BE VISIBLE |

The installer already does the following for you automatically, using the password you provided
at the "Virtuoso dba password" prompt:

1.  Set the `dba` superuser's password -- done automatically during installation, via Virtuoso's
    own `DBA_PASSWORD` startup setting. Your chosen password is stored (file mode 600) in the
    generated `.env` file. Unlike GraphDB, there's no separate "turn security on" step -- write
    access to Virtuoso's SPARQL Update endpoint always requires this password.
2.  Lock down anonymous reads. Virtuoso's unauthenticated `/sparql` endpoint can, by default, read
    every graph in the store. The installer runs a one-time SQL script
    (`virtuoso-initdb/lockdown-anonymous-sparql.sql`) when it first creates the database that
    removes this default, so all data access -- read or write -- now requires the same
    Digest-authenticated `dba` credentials.

Record data is written into per-record named graphs produced by the CARE-SM transformation
itself, in a single Virtuoso database rather than a separate "repository" per install (Virtuoso
has no such concept -- GraphDB did).

### Delete processed data files once they're safely loaded

`Sextans-Fix/data` is bind-mounted into `cde-box-daemon` and `yarrrml-rdfizer`, both of which run
as fixed-UID non-root users that generally won't match your host user -- so the install script
opens this folder to any local user (`chmod -R o+rwX`) so those containers can read and write it.
That means your source CSV and the generated RDF in `data/triples/` sit on disk, readable by any
local user on the host, for as long as you leave them there. Once you've confirmed a transformation
loaded successfully into Virtuoso, delete the CSV and `data/triples/*.nq` files rather than leaving
them in place -- they're not needed after a successful load, since the data of record from that
point on is what's in Virtuoso.




# CARE-SM Sextans Fix Quick Start!
<a name="testing"></a>
---

**Sextans Fix** is fully compatible with the **Clinical And Registry Entries Semantic Model (CARE-SM)**. This software implements a workflow that uses **CSV** and **YARRRML** templates to define the RDF shape and perform the transformation.

The only requirement is a **CSV template** that contains patient data based on CARE-SM. Once you have created and populated your CSV template(s), place the file(s) into the `Sextans-Fix/data` folder. 

---

## How to Populate the CSV?

An example CSV data file called **`Diagnosis.csv`** is included in `Sextans-Fix/data`. This file can be used as a default test option if you are unsure how to prepare your own template.  

If you want to use your own data, remove the `Diagnosis.csv` file and follow one of the options below:

1. **Map your own data:**  
   Check the [CARE-SM-2 Glossary documentation](https://care-sm-semantic-model-v2.readthedocs.io/en/latest/), which contains all the details needed for creating and populating your CSV template. If you're coming from the original CARE-SM's CSV schema, see the [Migrating from CARE-SM v1](https://care-sm-semantic-model-v2.readthedocs.io/en/latest/migration.html) page first -- several columns were renamed or restructured (e.g. Diagnosis's old `valueIRI` column is now `target`/`value`/`value_datatype`, with real boolean support).

2. **Use predefined synthetic data:**  
   CARE-SM-2 provides a set of synthetic CSV data tables for testing FiaB. You can find them [here](https://github.com/wilkinsonlab/CARE-Semantic-Model-Version-2/tree/main/implementation/CSV/).

> **Note:** CSV filenames are **not flexible**. They are controlled by a specific vocabulary described in the [CARE-SM-2 Glossary documentation](https://care-sm-semantic-model-v2.readthedocs.io/en/latest/).  

### Using your own datatype (not part of CARE-SM-2)

If you have data that doesn't fit any CARE-SM-2 model, you can bring your own CSV and your own
YARRRML mapping for it, entirely independent of the CARE-SM-2 pipeline above. Drop both into
`Sextans-Fix/data/custom/`, using matching basenames: `custom/<name>.csv` and
`custom/<name>_yarrrml.yaml`. Your mapping's own `source: access:` must point at the absolute
in-container path `/mnt/data/custom/<name>.csv`. Every transformation trigger picks up every
matching pair it finds there automatically -- no configuration needed beyond the two files
existing with matching names. A CSV with no matching mapping (or vice versa) is skipped with a
warning in the logs, not treated as an error; it won't block the CARE-SM-2 transformation.

Custom data lands in Virtuoso exactly like CARE-SM-2 data does. One thing to be aware of: each
transformation clears out the *previous* transformation's data before loading the new data (see
below) -- but only for graphs under your configured `baseURI`. If you want your custom data to
participate in that same replace-on-each-run behavior, mint its graphs under `baseURI` too;
otherwise it will simply accumulate across runs like Virtuoso's own normal behavior.

---

## Running the Transformation

Once your CSV data table is located in `Sextans-Fix/data`, you can trigger the transformation by opening  `http://localhost:4567/` in your web browser. 

Before doing anything else, the trigger pulls the latest CARE-SM-2 model/mapping from its
upstream repository, so every transformation always uses the current CARE-SM-2 release -- you
never need to manually update anything to get model improvements. That auto-pulled mapping is
smoke-tested against a small known-good fixture before it's trusted: if a fresh pull ever fails
that check (a broken or tampered upstream), the previous, already-verified mapping keeps being
used instead, and a warning is logged -- your transformation still runs, just against the last
mapping known to work.

After a few seconds, your output RDF data will appear under `Sextans-Fix/data/CARE/triples/`
(plus `data/custom-<name>/triples/` for each custom datatype, if any) and will also be
automatically uploaded into Virtuoso, into the per-record named graphs generated by the CARE-SM
transformation. Each run **replaces** the previous run's data (graphs under your configured
`baseURI` are cleared before the new data is loaded) rather than accumulating alongside it --
matching how the original GraphDB-backed pipeline behaved.