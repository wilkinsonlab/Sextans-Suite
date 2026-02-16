# Sextans Sight Installation

Sextans Sight is the Metadata service of the Sextans Suite.  

It consists of 4 "dockreized" components, all of them _mandatory_ and all of them _must be running at all times._

- FDP Client - Provides the Web front-end
- FDP Server - Provides the metadata access and talks to front-end
- MongoDB - holds database schema and user authentication information
- GraphDB - holds the RDF metadata for the overall service


## CONTENTS

- [Installation requirements](#requirements)
- [Downloading Sight](#downloading)
- [Installing Sight](#installing)
- [Testing your installation](#testing)

<a name="requirements"></a>

## Requirements

To use Sextans Sight you `must` meet the following requirements.

**User requirements (Person who is deploying this solution)**

- Basic knowledge about Docker​
- Basic GitHub knowledge​

**System requirements​ (Machine where this solution is being deployed)**

- Docker engine ​
- Docker-compose application​
- Accessible via HTTP(S) calls from your user community (local or global)

---

<a name="downloading"></a>

## Downloading

#### Sextans Sight

To get Sextans Sight clone this repository to your machine.

```sh
git clone https://github.com/wilkinsonlab/Sextans-Suite.git
```

---



## Installing


<a name="installing"></a>

## Preparing for Installation

At the beginning of the installation process you are asked three questions:

### A Prefix for your installation
The prefix is used as a "namespace" to isolate indepdent Sight installations from one another.  This allows you to run multiple Metadata servers on the same machine.  The prefix is used for the docker network, docker volumes, and appears in the configuration files and docker-compose yaml files.  This can be any set of letter/number characters.  Please do not use punctuation characters.  e.g. 'euronmd1'  We will use *'ACME'* for the remainder of this document.

### Your permanent GUID
For production installations, you should have already decided what your server URL will be, you should have already set up a Permanent Identifier redirect (e.g. using w3id), and you should already have a reverse proxy on your server to manage incoming requests from that redirect and point them at a specific localhost:PORT.  

For test installations, you can use a localhost:PORT address here.  Everything will work, but you cannot register your server in the central metadata index (e.g. the ERDERA VP Index). In this case, your PORT must match your answer to the next question about Sight Server port.

### Port for your Sight Server
This is the port that will be used by the FDP Client component.  This is validated against a list of "banned" ports (ports that are likely to be used by other software on your system).  It is a good idea to stay in the range of ~4000-10000.  If you have already set up an SSL proxy, this is the port that your proxy will point to.

### Port for your GraphDB
This is the port that will be used by the GraphDB metadata database component.  This is validated against a list of "banned" ports (ports that are likely to be used by other software on your system).  It is a good idea to stay in the range of ~4000-10000. 
By detault, this port is disabled after installation, so your graphdb cannot be accessed.  You will need to enable it, at least once, to login to GraphDB's web page and create a secure user for your Sight server (and change the login for the Admin user!).  This port does NOT need to be enabled for the regular operation of Sight, and should be disabled when not needed.


## Installing Sextans Sight

Once you have completed the "Downloading" section of this tutorial, and you have prepared your answers to the questions, cd into the `/Sight-install/` folder and run the instaler.

```
bash ./install-sextans-sight.sh
```

This script will bootstrap your FAIR Data Point and its associated GraphDB.  It creates a databases in GraphDB called *ACME-sextans-sight*. This is the database that you will need to secure after installation.

### If you abort installation before it completes...

This can (and probably will) leave you in a state that needs some careful attention.  In particular, find any graph-db Docker Volumes *_that have your PREFIX_* and remove them `docker volume rm ACME-graph-db`.  If it will not delete, it will be due to the existence of a docker container that uses it.  You can safely delete this docker container also.  `docker rm AJDIRDjdsfhwe83hewfewkw5`.  Again, make sure you are deleting the right things!


### The folder with your final server configuration

The installer will create a sub-folder `ACME-Sextans-Sight` underneath the folder where you ran your installation. This folder contains all of your server configuration files.  You can copy this folder anywhere on your system, e.g. to keep your servers all in one folder outside of your GitHub copy.  Inside that folder is a customized docker-compose file (docker-compose-ACME.yml) for your deployment.  So for example, you would issue the commands:

```

cp -r ACME-Sextans-Sight ~/SERVERS/
cd ~/SERVERS/ACME-Sextans-Sight
docker-compose -f docker-compose-ACME.yml up

```

Your Sight server is now running at whatever port you selected.

## Securing your Sextans Sight server

There are two components that you need to secure:  GraphDB and the FAIR Data Point Client.

These are the default login details and locations:

#### GraphDB

| Service name | Local deployment                                | Production deployment |
| ------------ | ----------------------------------------------- | --------------------- |
| GraphDB      | [http://localhost:7200](http://localhost:7200/) | SHOULD NOT BE VISIBLE |


| Username | Password |
| -------- | -------- |
| `admin`  | `root`   |

1.  Change the admin password
2.  Create a new user with read/write permissions on the *ACME-sextans-sight* database
3.  Ensure that secured access is switched ON


#### FAIR Data Point Client

| Service name    | Local deployment                               | Production deployment |
| --------------- | ---------------------------------------------- | --------------------- |
| FAIR Data Point | [http://localhost:7070](http://localhost:7070) | https://perma-url.org/path |


The default FAIR Data Point Client Administrator credentials are:

| Username                      | Password   |
| ----------------------------- | ---------- |
| `albert.einstein@example.com` | `password` |

1.  Remove the default Administrator and USER accounts
2.  Create a new Administrator account (if you don't do this immediately, you will be permanently locked-out and will need to start again!)
3.  You will need to login again
4.  If you want to create a USER type account, go ahead, but this is optional
5.  Login to the FDP and begin adding metadata (see tutorial at _______)

Note that you need the Administrator credentials to login to the FAIR Data Point API and get a token to do any API-based operation.


## Configuring your Sight server


#### Update the colors and logo

- go to the `ACME-Sextans-Sight/fdp` folder
- add your preferred logo file into the ./assets subfolder
- edit the ./variables.scss to point to that new logo file, and select its display size (or keep the default)
- to change the default colors, edit the first two lines to select the primary and secondary colors (the horizontal bar on the default http://localhost:7070 homepage shows the primary color on the left and the secondary color on the right)
- if you have a preferred favicon, replace the one in that folder with your preferred one.
- now go back to the ACME-Sextans-Sight folder and bring the docker-compose back up. Your FDP client will now be customized with your preferred icons and colors


#### Register with the central index

To register yourself with the central index of FAIR Data Points (e.g. the ERDERA FDP Index) you need to edit one file

```
~/SERVERS/ACME-Sextans-Sight/fdp/application.yml

```

The line you need to edit is:

```
    clientUrl: http://localhost:7070

```

Replace the `http://localhost:7070` URL with your own production URL (note that you should NOT include a trailing slash!).  The next time you docker-compose up, the system will register itself using the URL that you put as the value of clientUrl

To connect to the VP Index, you need to add the indexer "ping" function to your FAIR Data Point.  To do this:

- Login to your FDP via the Web page
- Go to "settings"
- About halfway down the settings there is a "Ping" section.  Add the following URL to the "Ping":
    - https://index.vp.ejprarediseases.org/

Once you have done this, the metadata you have added to your site will be indexed in the VP Index on the next "ping" cycle (should be weekly, by default).  THE INDEX WILL LOOK FOR THE "VPDiscoverable" tag in the vpConnection property of whatever resource(s) metadata you want to be indexed by the platform.  e.g. if you have 5 datasets, but you only want 3 of them to be indexed by the VP, then you set the vpConnection property to "VPDiscoverable" for ONLY those three datasets (the others have no value for that property). In the metadata editor of the FDP web page, this is done via a dropdown menu.

If you want to force re-indexing, you can shut-down (docker-compose down) and restart your FDP.  Alternatively, you can force a re-indexing by making the following `curl` command:

```
curl -X POST https://index.vp.ejprarediseases.org/ -H "Content-Type: application/json" -d
{"clientUrl": "https://my.perma-uri.address.here/}
```
(you cannot use your localhost address for this call)


###  IGNORE THIS FOR THE MOMENT

####These instructions are under review.  Please use them only for general reference purposes.

__Full instructions for modifying your default FAIR-in-a-box to match the schema requirements for the Virtual Platform can be found here:  https://github.com/ejp-rd-vp/FDP-Configuration__
