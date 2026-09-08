# Sextans Fix Installation

Sextans Fix is the FAIR data record component of the Sextans Suite.  It can be run independently of Sextans Sight, and is intended to be deployed on a separate network segment with appropriate security for handling (anonymized) clinical records.

It consists of 4 "dockreized" components, all of them _mandatory_, but with different requirements for activation.

- GraphDB - holds the RDF-formatted record data
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

### Port for your GraphDB
This is the port that will be used by the GraphDB database.  This is validated against a list of "banned" ports (ports that are likely to be used by other software on your system).  It is a good idea to stay in the range of ~4000-10000.  By detault, this port is disabled after installation, so your graphdb cannot be accessed.  This port does NOT need to be enabled for the regular operation of Sight, and should be disabled when not needed.

### Port for the transformation daemon
This is the port that will listen for requests to trigger a data transformation. It responds only to an "empty" HTTP GET request, does not allow any parameters, and does not process the HTTP request in any way.

### GraphDB admin password
GraphDB ships with a well-known default admin password. The installer asks you to choose a
replacement password (minimum 12 characters) and configures GraphDB with it automatically during
installation -- the image's default password is never left active. Keep this password somewhere
safe; it is also written (file mode 600) into the generated `.env` file in your production server
folder.


## Installing Sextans Fix

Once you have completed the "Downloading" section of this tutorial, and you have prepared your answers to the questions, cd into the `/Fix-install/` folder and run the instaler.

```
bash ./install-sextans-fix.sh
```

This script will bootstrap GraphDB.  It creates a databases in GraphDB called *ACME-sextans-fix*. This is the database that you will need to secure after installation.

### If you abort installation before it completes...

This can (and probably will) leave you in a state that needs some careful attention.  In particular, find any graph-db Docker Volumes *_that have your PREFIX_* and remove them `docker volume rm ACME-graph-db`.  If it will not delete, it will be due to the existence of a docker container that uses it.  You can safely delete this docker container also.  `docker rm AJDIRDjdsfhwe83hewfewkw5`.  Again, make sure you are deleting the right things!


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
GraphDB is secured as part of installation.

These are the default login details and locations:

#### GraphDB

| Service name | Local deployment                                | Production deployment |
| ------------ | ----------------------------------------------- | --------------------- |
| GraphDB      | [http://localhost:7200](http://localhost:7200/) | SHOULD NOT BE VISIBLE |

The installer already does the following for you automatically, using the password you provided
at the "GraphDB admin password" prompt:

1.  ~~Change the admin password~~ -- done automatically during installation, replacing GraphDB's
    default `admin`/`root` login. Your chosen password is stored (file mode 600) in the generated
    `.env` file.
2.  Ensure that secured access is switched ON -- done automatically during installation.

Still manual, if you need it: create an additional user with read/write permissions scoped to
just the *ACME-sextans-fix* database, if you want to hand out access without sharing the admin
login.




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
   Check to the [CARE-SM Glossary documentation](https://care-sm.readthedocs.io/en/latest/glossary.html), which contains all the details needed for creating and populating your CSV template.

2. **Use predefined synthetic data:**  
   CARE-SM provides a set of synthetic CSV data tables for testing FiaB. You can find them [here](https://github.com/CARE-SM/CARE-SM-Implementation/tree/main/CSV/).

> **Note:** CSV filenames are **not flexible**. They are controlled by a specific vocabulary described in the [CARE-SM Glossary documentation](https://care-sm.readthedocs.io/en/latest/glossary.html).  

---

## Running the Transformation

Once your CSV data table is located in `Sextans-Fix/data`, you can trigger the transformation by opening  `http://localhost:4567/` in your web browser. 

After a few seconds, your output RDF data will appear in the `Sextans-Fix/data/triples` folder and will also be automatically uploaded into GraphDB’s **`cde`** database.